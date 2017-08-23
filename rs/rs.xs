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
#include "c.h"

#define CALL	s[sp].st = NEW, sp += 1
#define RET(a)	v = a, sp -= 1

MODULE = rs		PACKAGE = rs

SV*
rs_parse(char *f)
	CODE:
		int	fd;
		errn1(fd = open(f, O_RDONLY));
		struct stat	b;
		errn1(fstat(fd, &b));
		char	*p;
		errn1((long int)(p = (char*)mmap(0, b.st_size, PROT_READ, MAP_PRIVATE, fd, 0)));
		errn1(close(fd));
		struct {
			enum {
				NEW, RK, RV
			}st;
			uint32_t	l;
			SV		*key;
			HV		*v;
		}s[256], *q;
		SV	*v;
		uc	sp = 1;
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
