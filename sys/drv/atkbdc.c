/* AT keybord controller driver */
#define KL_LOG KL_DEV
#include <sys/libkern.h>
#include <sys/vnode.h>
#include <sys/devfs.h>
#include <sys/klog.h>
#include <sys/condvar.h>
#include <sys/malloc.h>
#include <sys/ringbuf.h>
#include <sys/bus.h>
#include <dev/isareg.h>
#include <dev/atkbdcreg.h>
#include <sys/devclass.h>

/* XXX: resource size must be a power of 2 ?! */
#undef IO_KBDSIZE
#define IO_KBDSIZE 8

#define KBD_BUFSIZE 128

#define ATKBDC_VENDOR_ID 0x8086
#define ATKBDC_DEVICE_ID 0x7110 /* ISA! */

typedef struct atkbdc_state {
  spin_t lock;
  condvar_t nonempty;
  ringbuf_t scancodes;
  resource_t *irq_res;
  resource_t *regs;
} atkbdc_state_t;

/* For now, this is the only keyboard driver we'll want to have, so the
   interface is not very flexible. */

/* NOTE: These blocking wait helper functions can't use an interrupt, as the
   PS/2 controller does not generate interrupts for these events. However, this
   is not a major problem, since pretty much always the controller is
   immediately ready to proceed, so the we don't loop in practice. */
static inline void wait_before_read(resource_t *regs) {
  while (!(bus_read_1(regs, KBD_STATUS_PORT) & KBDS_KBD_BUFFER_FULL))
    ;
}

static inline void wait_before_write(resource_t *regs) {
  while (bus_read_1(regs, KBD_STATUS_PORT) & KBDS_INPUT_BUFFER_FULL)
    ;
}

static void write_command(resource_t *regs, uint8_t command) {
  wait_before_write(regs);
  bus_write_1(regs, KBD_COMMAND_PORT, command);
}

static uint8_t read_data(resource_t *regs) {
  wait_before_read(regs);
  return bus_read_1(regs, KBD_DATA_PORT);
}

static void write_data(resource_t *regs, uint8_t byte) {
  wait_before_write(regs);
  bus_write_1(regs, KBD_DATA_PORT, byte);
}

static int scancode_read(vnode_t *v, uio_t *uio, int ioflag) {
  atkbdc_state_t *atkbdc = devfs_node_data(v);
  int error;

  uio->uio_offset = 0; /* This device does not support offsets. */

  WITH_SPIN_LOCK (&atkbdc->lock) {
    uint8_t data;
    /* For simplicity, copy to the user space one byte at a time. */
    while (!ringbuf_getb(&atkbdc->scancodes, &data))
      cv_wait(&atkbdc->nonempty, &atkbdc->lock);
    if ((error = uiomove_frombuf(&data, 1, uio)))
      return error;
  }

  return 0;
}

static vnodeops_t scancode_vnodeops = {
  .v_read = scancode_read,
};

/* Reset keyboard and perform a self-test. */
static bool kbd_reset(resource_t *regs) {
  write_data(regs, KBDC_RESET_KBD);
  uint8_t response = read_data(regs);
  if (response != KBD_ACK)
    return false;
  return (read_data(regs) == KBD_RESET_DONE);
}

static intr_filter_t atkbdc_intr(void *data) {
  atkbdc_state_t *atkbdc = data;

  if (!(bus_read_1(atkbdc->regs, KBD_STATUS_PORT) & KBDS_KBD_BUFFER_FULL))
    return IF_STRAY;

  /* TODO: Some locking mechanism will be necessary if we want to sent extra
     commands to the ps/2 controller and/or other ps/2 devices, because this
     thread would interfere with commands/responses. */
  uint8_t code = read_data(atkbdc->regs);
  uint8_t code2 = 0;
  bool extended = (code == 0xe0);

  if (extended)
    code2 = read_data(atkbdc->regs);

  WITH_SPIN_LOCK (&atkbdc->lock) {
    /* TODO: There's no logic for processing scancodes. */
    ringbuf_putb(&atkbdc->scancodes, code);
    if (extended)
      ringbuf_putb(&atkbdc->scancodes, code2);
    cv_signal(&atkbdc->nonempty);
  }

  return IF_FILTERED;
}

static int atkbdc_probe(device_t *dev) {
  if (dev->unit != 0) /* XXX: unit 0 assigned by gt_pci */
    return 0;

  resource_t *regs = device_take_ioports(dev, 0, RF_ACTIVE);
  assert(regs != NULL);

  if (!kbd_reset(regs)) {
    klog("Keyboard self-test failed.");
    return 0;
  }

  /* Enable scancode table #1 */
  write_data(regs, KBDC_SET_SCANCODE_SET);
  write_data(regs, 1);
  if (read_data(regs) != KBD_ACK)
    return 0;

  /* Start scanning. */
  write_data(regs, KBDC_ENABLE_KBD);
  if (read_data(regs) != KBD_ACK)
    return 0;

  return 1;
}

static int atkbdc_attach(device_t *dev) {
  atkbdc_state_t *atkbdc = dev->state;

  atkbdc->scancodes.data = kmalloc(M_DEV, KBD_BUFSIZE, M_ZERO);
  atkbdc->scancodes.size = KBD_BUFSIZE;

  spin_init(&atkbdc->lock, 0);
  cv_init(&atkbdc->nonempty, "AT keyboard buffer non-empty");
  atkbdc->regs = device_take_ioports(dev, 0, RF_ACTIVE);
  assert(atkbdc->regs != NULL);

  atkbdc->irq_res = device_take_irq(dev, 0, RF_ACTIVE);
  bus_intr_setup(dev, atkbdc->irq_res, atkbdc_intr, NULL, atkbdc,
                 "AT keyboard controller");

  /* Enable interrupt */
  write_command(atkbdc->regs, KBDC_SET_COMMAND_BYTE);
  write_data(atkbdc->regs, KBD_ENABLE_KBD_INT);

  /* Prepare /dev/scancode interface. */
  devfs_makedev(NULL, "scancode", &scancode_vnodeops, atkbdc, NULL);

  return 0;
}

static driver_t atkbdc_driver = {
  .desc = "AT keyboard controller driver",
  .size = sizeof(atkbdc_state_t),
  .pass = SECOND_PASS,
  .probe = atkbdc_probe,
  .attach = atkbdc_attach,
};

DEVCLASS_ENTRY(isa, atkbdc_driver);
