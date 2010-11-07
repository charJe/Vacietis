/* -*- Mode: C; Tab-width: 5; Base: 10 -*-

	Copyright (C) 1986 by ZETA-SOFT, Ltd.
	All rights reserved.

 SGTTY.H for ZETA-C: declarations for stty(), gtty(), and ioctl().
 (Note that only part of the UNIX functionality is provided.)
 Note this file does not have a package specification, as it will be
 read into (potentially) many different packages. */

struct sgttyb {
	char	sg_ispeed;	/* input speed */
	char	sg_ospeed;	/* output speed */
	char	sg_erase;		/* erase character */
	char	sg_kill;		/* kill character */
	int	sg_flags;		/* mode flags */
};

/* Modes -- only ECHO, RAW, and CBREAK work. */
#define	TANDEM	01
#define	CBREAK	02
#define	LCASE	04
#define	ECHO		010
#define	CRMOD	020
#define	RAW		040
#define	ODDP		0100
#define	EVENP	0200
#define	ANYP		0300
#define	NLDELAY	001400
#define	LLITOUT	0100040
#define	TBDELAY	006000
#define	XTABS	06000
#define	CRDELAY	030000
#define	VTDELAY	040000
#define	BSDELAY	0100000
#define	ALLDELAY	0177400

/* Delay algorithms (none of these are implemented) */
#define	CR0	0
#define	CR1	010000
#define	CR2	020000
#define	CR3	030000
#define	NL0	0
#define	NL1	000400
#define	NL2	001000
#define	NL3	001400
#define	TAB0	0
#define	TAB1	002000
#define	TAB2	004000
#define	FF0	0
#define	FF1	040000
#define	BS0	0
#define	BS1	0100000

/* Speeds (ignored) */
#define B0	0
#define B50	1
#define B75	2
#define B110	3
#define B134	4
#define B150	5
#define B200	6
#define B300	7
#define B600	8
#define B1200	9
#define B1800	10
#define B2400	11
#define B4800	12
#define B9600	13
#define EXTA	14
#define EXTB	15
#define B7200	14
#define B19200	15

/* tty ioctl commands -- only TIOCGETP, TIOCSETP, TIOCSETN, and FIONREAD implemented */
#define	TIOCGETD	(('t'<<8)|0)
#define	TIOCSETD	(('t'<<8)|1)
#define	TIOCHPCL	(('t'<<8)|2)
#define	TIOCMODG	(('t'<<8)|3)
#define	TIOCMODS	(('t'<<8)|4)
#define	TIOCGETP	(('t'<<8)|8)
#define	TIOCSETP	(('t'<<8)|9)
#define	TIOCSETN	(('t'<<8)|10)
#define	TIOCEXCL	(('t'<<8)|13)
#define	TIOCNXCL	(('t'<<8)|14)
#define	TIOHMODE	(('t'<<8)|15)
#define	TIOCFLUSH	(('t'<<8)|16)
#define	TIOCSETC	(('t'<<8)|17)
#define	TIOCGETC	(('t'<<8)|18)
#define	TIOCEMPTY	(('t'<<8)|19)
#define	DIOCLSTN	(('d'<<8)|1)
#define	DIOCNTRL	(('d'<<8)|2)
#define	DIOCMPX	(('d'<<8)|3)
#define	DIOCNMPX	(('d'<<8)|4)
#define	DIOCSCALL	(('d'<<8)|5)
#define	DIOCRCALL	(('d'<<8)|6)
#define	DIOCPGRP	(('d'<<8)|7)
#define	DIOCGETP	(('d'<<8)|8)
#define	DIOCSETP	(('d'<<8)|9)
#define	DIOCLOSE	(('d'<<8)|10)
#define	DIOCTIME	(('d'<<8)|11)
#define	DIOCRESET	(('d'<<8)|12)
#define	FIOCLEX	(('f'<<8)|1)
#define	FIONCLEX	(('f'<<8)|2)
#define	FIONREAD	(('f'<<8)|3)
#define	MXLSTN	(('x'<<8)|1)
#define	MXNBLK	(('x'<<8)|2)

/* End of SGTTY.H */
