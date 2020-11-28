/*
	Copyright © 2018 Yang Bo

	This file is part of RSLinux.

	RSLinux is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	RSLinux is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with RSLinux.  If not, see <http://www.gnu.org/licenses/>.
 */
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <string.h>

#include <stdio.h>
#include <stdlib.h>

#include "fuse.h"

#define STR(a)	#a
#define STR1(a)	STR(a)
#define WRAP(a)					\
	do {					\
		a;				\
	} while (0)
#define croak_if(cond, s)						\
	WRAP(if (cond) {						\
		perror("File " __FILE__ ", line " STR1(__LINE__) ", " s); \
		exit(~0);						\
	})
#define errn1(a)	croak_if((a) == -1, "("#a") == -1")
#define unless(a)	if (!(a))

#define CALL	s[sp].st = NEW, sp += 1
#define RET(a)	v = a, sp -= 1

#define BLKSZ	4096
#define FLUSH	errn1(write(fd, ou, ol)); ol = 0

#define LLAC(a)		s[sp].st = NEW, sp += 1, v = a
#define TER		sp -= 1
#define HPACK(t, l)	*p = t, *(uint32_t*)(p + 1) = (uint32_t)l, cwrite(fd, p, 5)

static void *mmapr(const char *f, off_t *l)
{
	int	fd;
	errn1(fd = open(f, O_RDONLY));
	struct stat	b;
	errn1(fstat(fd, &b));
	if (l)	*l = b.st_size;
	void	*p = NULL;
	if (b.st_size)
		errn1((long int)(p = mmap(0, b.st_size, PROT_READ, MAP_PRIVATE, fd, 0)));
	errn1(close(fd));
	return p;
}
static void cwrite(int fd, const char *in, size_t il)
{
	static char	ou[BLKSZ];
	static size_t	ol;
	unless (in) {
		FLUSH;
		return;
	}
	while (il) {
		if (ol + il >= BLKSZ) {
			if (ol == 0) {
				errn1(write(fd, in, il));
				il = 0;
			} else {
				size_t	l = BLKSZ - ol;
				memcpy(ou + ol, in, l); ol += l, in += l, il -= l;
				FLUSH;
			}
		} else {
			memcpy(ou + ol, in, il); ol += il, il = 0;
		}
	}
}

MODULE = App::rs		PACKAGE = App::rs

SV*
rs_parse(char *f)
	CODE:
		char	*p = (char*)mmapr(f, NULL);
		struct {
			enum {
				NEW, RK, RV
			}st;
			uint32_t	l;
			SV		*key;
			HV		*v;
		}s[256], *q;
		SV	*v;
		uint8_t	sp = 0;
		CALL;
		while (sp) {
			q = s + sp - 1;
			if (q->st == NEW) {
				char		t = *p++;
				uint32_t	l = *(uint32_t*)p;
				p += 4;
				if (t == 'S') {
					v = newSV(0);
					SvUPGRADE(v, SVt_PV);
					SvPVX(v) = p, SvCUR_set(v, l), SvLEN_set(v, 0);
					SvPOK_only(v);
					p += l, sp -= 1;
				} else {
					if (l) {
						q->v = newHV(), q->l = l, q->st = RK;
						CALL;
					} else {
						RET(newRV_noinc((SV*)newHV()));
					}
				}
			} else {
				if (q->st == RK) {
					q->key = v, q->st = RV;
					CALL;
				} else {
					hv_store_ent(q->v, q->key, v, 0);
					if (q->l -= 1) {
						q->st = RK;
						CALL;
					} else {
						RET(newRV_noinc((SV*)q->v));
					}
				}
			}
		}
		RETVAL = v;
	OUTPUT:
		RETVAL

void
rs_unparse(SV *v, int fd)
	CODE:
		char	p[5];
		struct {
			enum {
				NEW, OLD
			}st;
			HV	*v;
		}s[256], *q;
		uint8_t	sp = 0;
		LLAC(v);
		while (sp) {
			q = s + sp - 1;
			if (q->st == NEW) {
				unless (SvROK(v)) {
					char	*in;
					STRLEN	il;
					in = SvPV(v, il);
					HPACK('S', il);
					cwrite(fd, in, il);
					TER;
				} else {
					v = SvRV(v);
					if (SvTYPE(v) < SVt_PVAV) {
						off_t	il;
						char	*in = (char*)mmapr(SvPV_nolen(v), &il);
						HPACK('S', il);
						if (il) {
							cwrite(fd, in, il);
							errn1(munmap(in, il));
						}
						TER;
					} else {
						q->v = (HV*)v, q->st = OLD;
						uint32_t	l = 0;
						hv_iterinit(q->v);
						while (hv_iternext(q->v))	l += 1;
						HPACK('H', l);
						hv_iterinit(q->v);
					}
				}
			} else {
				char	*key;
				I32	retlen;
				v = hv_iternextsv(q->v, &key, &retlen);
				if (v) {
					HPACK('S', retlen);
					cwrite(fd, key, retlen);
					LLAC(v);
				} else {
					TER;
				}
			}
		}
		cwrite(fd, NULL, 0);

bool
lchown(char *f, uid_t uid, gid_t gid)
	POSTCALL:
		RETVAL = !RETVAL;

bool
utimensat(char *f, int t)
	CODE:
		struct timespec	times[2];
		times[0].tv_nsec = UTIME_OMIT;
		times[1].tv_sec = t, times[1].tv_nsec = 0;
		RETVAL = !utimensat(AT_FDCWD, f, times, AT_SYMLINK_NOFOLLOW);
	OUTPUT:
		RETVAL

void
fuse_main(HV *_)
