#! /bin/sh -
#	$OpenBSD: makesyscalls.sh,v 1.13 2016/09/26 16:42:34 jca Exp $
#	$NetBSD: makesyscalls.sh,v 1.26 1998/01/09 06:17:51 thorpej Exp $
#
# Copyright (c) 1994,1996 Christopher G. Demetriou
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. All advertising materials mentioning features or use of this software
#    must display the following acknowledgement:
#      This product includes software developed for the NetBSD Project
#      by Christopher G. Demetriou.
# 4. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#	@(#)makesyscalls.sh	8.1 (Berkeley) 6/10/93

set -e

case $# in
    2)	;;
    *)	echo "Usage: $0 config-file input-file" 1>&2
	exit 1
	;;
esac

# source the config file.
case $1 in
    /*)	. $1
	;;
    *)	. ./$1
	;;
esac

# the config file sets the following variables:
#	sysnumhdr: the syscall numbers file
#	syssw: the syscall switch file
#	sysarghdr: the syscall argument struct definitions
#	switchname: the name for the 'struct sysent' we define

# tmp files:
sysdcl="sysent.dcl"
syscompat_pref="sysent."
sysent="sysent.switch"

trap "rm $sysdcl $sysent" 0

# Awk program (must support nawk extensions)
# Use "awk" at Berkeley, "nawk" or "gawk" elsewhere.
awk=${AWK:-awk}

# Does this awk have a "toupper" function? (i.e. is it GNU awk)
isgawk=`$awk 'BEGIN { print toupper("true"); exit; }' 2>/dev/null`

# If this awk does not define "toupper" then define our own.
if [ "$isgawk" = TRUE ] ; then
	# GNU awk provides it.
	toupper=
else
	# Provide our own toupper()
	toupper='
function toupper(str) {
	_toupper_cmd = "echo "str" |tr a-z A-Z"
	_toupper_cmd | getline _toupper_str;
	close(_toupper_cmd);
	return _toupper_str;
}'
fi

# before handing it off to awk, make a few adjustments:
#	(1) insert spaces around {, }, (, ), *, and commas.
#	(2) get rid of any and all dollar signs (so that rcs id use safe)
#
# The awk script will deal with blank lines and lines that
# start with the comment character (';').

sed -e '
s/\$//g
:join
	/\\$/{a\

	N
	s/\\\n//
	b join
	}
2,${
	/^#/!s/\([{}()*,]\)/ \1 /g
}
' < $2 | $awk "
$toupper
BEGIN {
	# to allow nested #if/#else/#endif sets
	savedepth = 0

	sysnumhdr = \"$sysnumhdr\"
	sysarghdr = \"$sysarghdr\"
	switchname = \"$switchname\"
	namesname = \"$namesname\"

	sysdcl = \"$sysdcl\"
	syscompat_pref = \"$syscompat_pref\"
	sysent = \"$sysent\"
	infile = \"$2\"

	syscall = 0

	"'

	printf "/*\n * System call switch table.\n *\n" > sysdcl
	printf " * DO NOT EDIT: this file is automatically generated.\n" > sysdcl

	printf "struct sysent %s[] = {\n",switchname > sysent

	printf "/*\n * System call numbers.\n *\n" > sysnumhdr
	printf " * DO NOT EDIT: this file is automatically generated.\n" > sysnumhdr

	printf "/*\n * System call argument lists.\n *\n" > sysarghdr
	printf " * DO NOT EDIT: this file is automatically generated.\n" > sysarghdr
}
NR == 1 {
	printf " * created from%s\n */\n\n", $0 > sysdcl

	printf " * created from%s\n */\n\n", $0 > sysnumhdr

	printf " * created from%s\n */\n\n", $0 > sysarghdr
	next
}
NF == 0 || $1 ~ /^;/ {
	next
}
$1 ~ /^#[ 	]*include/ {
	print > sysarghdr
	next
}
$1 ~ /^#[ 	]*if/ {
	print > sysent
	savesyscall[++savedepth] = syscall
	next
}
$1 ~ /^#[ 	]*else/ {
	print > sysent
	if (savedepth <= 0) {
		printf "%s: line %d: unbalanced #else\n", \
		    infile, NR
		exit 1
	}
	syscall = savesyscall[savedepth]
	next
}
$1 ~ /^#/ {
	if ($1 ~ /^#[       ]*endif/) {
		if (savedepth <= 0) {
			printf "%s: line %d: unbalanced #endif\n", \
			    infile, NR
			exit 1
		}
		savedepth--;
	}
	print > sysent
	next
}
syscall != $1 {
	printf "%s: line %d: syscall number out of sync at %d\n", \
	   infile, NR, syscall
	printf "line is:\n"
	print
	exit 1
}
function parserr(was, wanted) {
	printf "%s: line %d: unexpected %s (expected %s)\n", \
	    infile, NR, was, wanted
	exit 1
}
function parseline() {
	f=2			# toss number and type
	if ($NF != "}") {
		funcalias=$NF
		end=NF-1
	} else {
		funcalias=""
		end=NF
	}
	if ($f ~ /^[a-z0-9_]*$/) {      # allow syscall alias
		funcalias=$f
		f++
	}	
	if ($f != "{")
		parserr($f, "{")
	f++
	if ($end != "}")
		parserr($end, "}")
	end--
	if ($end != ";")
		parserr($end, ";")
	end--
	if ($end != ")")
		parserr($end, ")")
	end--

	returntype = oldf = "";
	do {
		if (returntype != "" && oldf != "*")
			returntype = returntype" ";
		returntype = returntype$f;
		oldf = $f;
		f++
	} while (f < (end - 1) && $(f+1) != "(");
	if (f == (end - 1)) {
		parserr($f, "function argument definition (maybe \"(\"?)");
	}

	funcname=$f
	if (funcalias == "") {
		funcalias=funcname
		sub(/^([^_]+_)*sys_/, "", funcalias)
	}
	f++

	if ($f != "(")
		parserr($f, ")")
	f++

	argc=0;
	if (f == end) {
		if ($f != "void")
			parserr($f, "argument definition")
		isvarargs = 0;
		varargc = 0;
		return
	}

	# some system calls (open() and fcntl()) can accept a variable
	# number of arguments.  If syscalls accept a variable number of
	# arguments, they must still have arguments specified for
	# the remaining argument "positions," because of the way the
	# kernel system call argument handling works.
	#
	# Indirect system calls, e.g. syscall(), are exceptions to this
	# rule, since they are handled entirely by machine-dependent code
	# and do not need argument structures built.

	isvarargs = 0;
	while (f <= end) {
		if ($f == "...") {
			f++;
			isvarargs = 1;
			varargc = argc;
			continue;
		}
		argc++
		argtype[argc]=""
		oldf=""
		while (f < end && $(f+1) != ",") {
			if (argtype[argc] != "" && oldf != "*")
				argtype[argc] = argtype[argc]" ";
			argtype[argc] = argtype[argc]$f;
			oldf = $f;
			f++
		}
		if (argtype[argc] == "")
			parserr($f, "argument definition")
		argname[argc]=$f;
		f += 2;			# skip name, and any comma
	}
	# must see another argument after varargs notice.
	if (isvarargs) {
		if (argc == varargc)
			parserr($f, "argument definition")
	} else
		varargc = argc;
}
function putent() {
	# output syscall declaration for switch table
	if (argc != 0)
		printf("static int %s(proc_t *, %s_args_t *, register_t *);\n",
		       funcname, funcalias) > sysdcl
	else
		printf("static int %s(proc_t *, void *, register_t *);\n",
		       funcname) > sysdcl

	# output syscall switch table entry
	printf("  [SYS_%s] = { (syscall_t *)%s },\n",
	       funcalias, funcname) > sysent

	# output syscall number of header
	printf("#define SYS_%s %d\n", funcalias, syscall) > sysnumhdr

	# output syscall argument structure, if it has arguments
	if (argc != 0) {
		printf("\ntypedef struct {\n") > sysarghdr
		for (i = 1; i <= argc; i++)
			printf("  %s %s;\n", argtype[i], argname[i]) > sysarghdr
		printf("} %s_args_t;\n", funcalias) > sysarghdr
	}
}
{
	parseline()
	putent();
	syscall++
	next
}
END {
	printf("};\n\n") > sysent
	printf("\n") > sysdcl
	printf("#define SYS_%s %d\n", "MAXSYSCALL", syscall) > sysnumhdr
} '

cat $sysdcl $sysent > $syssw

# vim: ts=8 sw=8 noet
