#!/bin/perl -w
=license

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

=cut
# dedicated to Robert Schumann.
use strict;
use c;
use cxs;

my %filetype = (
	0140000 => "socket",
	0120000 => "symbolic link",
	0100000 => "regular file",
	0060000 => "block device",
	0040000 => "directory",
	0020000 => "character device",
	0010000 => "fifo"
    );
BEGIN {
	$SIG{__WARN__} = sub {
		return if $_[0] =~ /^Possible attempt to separate words with commas/;
		warn @_;
	};
}
my %B = (
	gcc => {
		switch => [qw/--disable-bootstrap --enable-languages=c,c++ --disable-multilib/]
	},
	ncurses => {
		switch => [qw/--enable-widec --with-shared/],
	},
	bash => {
		switch => [qw/--with-curses/],
	},
	"pkg-config" => {
		switch => [qw/--with-internal-glib/],
	},
	Python => {
		switch => [qw/--enable-shared/],
	},
	kbd => {
		switch => [qw/--disable-vlock/],
	},
	wget => {
		switch => [qw/--with-ssl=openssl --with-openssl/],
	},
	lynx => {
		switch => [qw/--enable-ipv6 --with-ssl --with-screen=ncursesw/],
	},
	"alsa-utils" => {
		switch => [qw/--disable-xmlto/],
	},
	mesa => {
		switch => [qw/--with-dri-drivers=i965 --with-gallium-drivers=/],
	},
	"xorg-server" => {
		switch => [qw|--with-fontrootdir=/share/fonts/X11|],
		postmi => 'chmod u+s /bin/Xorg',
	},
	libtirpc => {
		switch => [qw/--disable-gssapi/],
	},
	"nfs-utils" => {
		switch => [qw/--disable-gss --disable-nfsv4 --without-tcp-wrappers/],
	},
	emacs => {
		switch => [qw/--without-x --with-file-notification=inotify/],
	},
	ffmpeg => {
		switch => [qw/--enable-libfreetype --enable-libx264 --enable-gpl --enable-x11grab/]
	},
	qemu => {
		switch => [qw|--extra-cflags=-I/include/ncursesw --cc=gcc --target-list=i386-softmmu,x86_64-softmmu,arm-linux-user --audio-drv-list=alsa|],
	},
	"procps-ng" => {
		env => { CPPFLAGS => "-I/include/ncursesw" },
	},
	psmisc => {
		env => { CPPFLAGS => "-I/include/ncursesw" },
	},
	"man-pages" => {
		noc => 1,
		nomk => 1,
	},
	kmod => {
		postmi => 'for i in {lsmod,rmmod,insmod,modinfo,modprobe,depmod}; do ln -s /bin/kmod /sbin/$i; done',
	},
	pciutils => {
		noc => 1,
		miparam => ["PREFIX=/"],
	},
	"XML-Parser" => {
		noc => 1,
		postc => 'perl Makefile.PL',
	},
	sysvinit => {
		noc => 1,
		mkparam => ["CC=gcc"],
	},
	dosfstools => {
		noc => 1,
		mkparam => ["CC=gcc"],
		miparam => ["PREFIX=/"],
	},
	rtmpdump => {
		noc => 1,
		mkparam => ["SYS=posix"],
		miparam => ["prefix=/"]
	},
	wine => {
		env => { CPPFLAGS => "-I/include/ncursesw" },
	},
	syslinux => {
		noc => 1,
		miparam => ["INSTALLROOT=/"],
	},
	"terminus-font" => {
		switch => ["--x11dir=/share/fonts/X11/terminus"],
		postmi => 'mkfontdir /share/fonts/X11/terminus'
	},
	"poppler-data" => {
		noc => 1,
		nomk => 1,
		miparam => ["prefix=/"]
	},
	unrarsrc => {
		noc => 1,
		miparam => ["DESTDIR=/"]
	},
	unzip => {
		noc => 1,
		mkparam => [qw|CC=gcc generic -f unix/Makefile|],
		miparam => [qw|prefix=/ install -f unix/Makefile|]
	},
	zip => {
		noc => 1,
		mkparam => [qw|generic_gcc -f unix/Makefile|],
		miparam => [qw|prefix=/ install -f unix/Makefile|]
	},
	icecat => {
		switch => [qw/--disable-dbus --disable-pulseaudio --disable-gstreamer --disable-necko-wifi/]
	},
	wireshark => {
		switch => [qw/--with-gtk2 --enable-setuid-install/]
	},
	x264 => {
		switch => [qw/--enable-static --enable-shared/]
	}
    );
=c
qt5:
	./configure -prefix / -archdatadir /share/qt -datadir /share/qt -examplesdir /share/qt/examples -hostdatadir /share/qt -opensource -nomake tests -qt-xcb -no-dbus
qt4:
	./configure -prefix / -docdir /share/qt4/doc -plugindir /share/qt4/plugins -importdir /share/qt4/imports -datadir /share/qt4 -translationdir /share/qt4/translations -examplesdir /share/qt4/examples -demosdir /share/qt4/demos -opensource -nomake tests
	tests is still installed under /, mannually move is required.
=cut

sub pson_unparse {
	my $a = shift;
	my $ans;
	if (ref $a eq "ARRAY") {
		$ans .= "A" . pack("L", ~~@$a);
		$ans .= pson_unparse($_) for (@$a);
	} elsif (ref $a eq "HASH") {
		$ans .= "H" . pack("L", ~~keys %$a);
		$ans .= pson_unparse($_) . pson_unparse($a->{$_}) for (keys %$a);
	} else {
		$ans .= "S" . pack("L", length($a)) . $a;
	}
	return $ans;
}
sub pson_unparse_w {
	my ($a, $fh) = @_;
	if (ref $a eq "ARRAY") {
		syswrite $fh, "A" . pack("L", ~~@$a);
		pson_unparse_w($_, $fh) for (@$a);
	} elsif (ref $a eq "HASH") {
		syswrite $fh, "H" . pack("L", ~~keys %$a);
		for (keys %$a) {
			pson_unparse_w($_, $fh);
			pson_unparse_w($a->{$_}, $fh);
		}
	} elsif (ref $a eq "REF") {
		my $p = $$a;
		if ($p->{type} eq "substr") {
			syswrite $fh, "S" . pack("L", $p->{length});
			cxs::write(fileno($fh), $p->{strref}, $p->{offset}, $p->{length}) or die "cxs::write";
		} elsif ($p->{type} eq "mmap") {
			if (cxs::mmap($p->{f}, my $b)) {
				syswrite $fh, "S" . pack("L", length($b));
				syswrite $fh, $b;
				cxs::munmap($b, length($b));
			} else {
				syswrite $fh, "S" . pack("L", 0);
			}
		}
	} else {
		syswrite $fh, "S" . pack("L", length($a)) . $a;
	}
}
=c
sub pson_parse_wrap {
	my $a = shift;
	return (pson_parse(\$a, 0))[0];
}
=cut
sub pson_parse {
	my ($p, $i) = @_;
	my ($a, $f) = @{$p}{qw/strref flag/};
	my $t = substr($$a, $i, 1);
	my $l = unpack("L", substr($$a, $i+1, 4));
	$i += 5;
	my $ans;
	if ($t eq "A") {
		$ans = [];
		while ($l--) {
			my $v;
			($v, $i) = pson_parse($p, $i);
			push @$ans, $v;
		}
	} elsif ($t eq "H") {
		$ans = {};
		while ($l--) {
			my ($key, $v);
			($key, $i) = pson_parse({strref => $a}, $i);
			($v, $i) = pson_parse($p, $i);
			$ans->{$key} = $v;
		}
	} else {
		if ($f) {
			my $h = {
				type => "substr",
				strref => $a,
				offset => $i,
				length => $l
			};
			$ans = \$h;
		} else {
			$ans = substr($$a, $i, $l);
		}
		$i += $l;
	}
	return ($ans, $i);
}
sub walk {
	my ($p, $d) = @_;
	$d = "" unless $d;
	my $ans = {};
	opendir(my $dh, $p->{root} . $d) or die $!;
      p0:
	for (sort readdir $dh) {
		next if /^\.{1,2}$/;
		my ($r, $f) = ($d . $_, $p->{root} . $d . $_);
		for (@{$p->{exclude}}) {
			if ($_ eq $r) {
				print "$f is excluded.\n";
				next p0;
			}
		}
		$ans->{$_} = {};
		(my $i, @{$ans->{$_}}{qw/mode uid gid mt/}) = (lstat($f))[1, 2, 4, 5, 9];
		if ($p->{ih}{$i})	{ $ans->{$_}{hl} = $p->{ih}{$i} }
		else			{ $p->{ih}{$i} = $r }
		if (-d _) {
			if (-x _)	{ $ans->{$_}{c} = walk($p, $r . "/") }
			else		{ print $f . "/", " is a directory but not executable.\n" }
		}
	}
	return $ans;
}
# difference of entry.
sub de {
	my ($f, $p, $q) = @_;
	my $d = 0;
	for (qw/mode uid gid mt hl/) {
		my ($a, $b) = ($p->{$_} // "", $q->{$_} // "");
		if ($a ne $b) {
			$d++;
			if ($_ eq "mode") {
				$_ = sprintf "%.7o", $_ for ($a, $b);
			} elsif ($_ eq "mt") {
				$_ = localtime($_) for ($a, $b);
			}
			print $f, " $_ differs, previous: $a, now: $b.\n";
		}
	}
	$d;
}
sub check {
	my ($p, $h, $d) = @_;
	$d = "" unless $d;
	my $ans = {};
	for (sort keys %$h) {
		my $r = $d . $_;
		my $f = $p->{root} . $r;
		my $e = {};
		(my $i, @{$e}{qw/mode uid gid mt/}) = (lstat($f))[1, 2, 4, 5, 9];
		if ($i) {
			if ($p->{ih}{$i})	{ $e->{hl} = $e->{c} = $p->{ih}{$i} }
			else			{ $p->{ih}{$i} = $r }
			if (-d _ and ref $h->{$_}{c} eq "HASH") {
				$e->{c} = check($p, $h->{$_}{c}, $d . $_ . "/");
				$ans->{$_} = $e if %{$e->{c}}
			} else {
				if (de($f, $h->{$_}, $e)) {
					$e->{ow} = 1;
					my $t = $filetype{$e->{mode} & 0170000};
					$e->{c} = readlink $f if $t eq "symbolic link";
					$ans->{$_} = $e;
				}
			}
		} else {
			$ans->{$_} = $h->{$_};
		}
	}
	$ans;
}
sub diff {
	my ($p, $q, $d) = @_;
	$d = "" unless $d;
	my $ans = {};
	for (keys %$q) {
		my $f = $d . $_;
		my ($ne, $ow);
		if ($p and $p->{$_}) {
			my $tp = $filetype{$p->{$_}{mode} & 0170000};
			my $tq = $filetype{$q->{$_}{mode} & 0170000};
			if ($tp eq "directory" and $tq eq "directory") {
				my $t = diff($p->{$_}{c}, $q->{$_}{c}, $f . "/");
				if (%$t) {
					print "$f exist but contents inside differ.\n";
					$ans->{$_} = {%{$q->{$_}}}, $ans->{$_}{c} = $t;
				}
			} else {
				$ow = de($f, $p->{$_}, $q->{$_});
			}
		} else {
			$ne = 1;
		}
		if ($ne or $ow) {
			print "$f\n";
			print "\e[36m", "added since it's been overwritten.\n", "\e[m" if $ow;
			my $c;
			my $t = $filetype{$q->{$_}{mode} & 0170000};
			if ($t eq "directory") {
				$c = diff(undef, $q->{$_}{c}, $f . "/");
			} elsif ($t eq "regular file") {
				if ($f =~ /\.la$/) {
					print "remove la file $f...";
					if (unlink $f)	{ print "successed.\n" }
					else		{ print "failed.\n" }
				} else {
					if (c::xsh(1, "file", $f) =~ /(executable|shared object).*not stripped/) {
						print "trying to strip $f...";
						c::xsh(0, "strip", $f);
						unless ($?) {
							print "successed.\n";
							set($f, @{$q->{$_}}{qw/mode uid gid mt/});
						} else {
							print "failed.\n";
						}
					}
					if ($q->{$_}{hl})	{ $c = $q->{$_}{hl} }
					else {
						my $h = {
							type => "mmap",
							f => $f
						};
						$c = \$h;
					}
				}
			} elsif ($t eq "symbolic link") {
				$c = readlink $f or die $!;
			} else {
				print "unable to handle file type $t of file $f.\n";
			}
			if ($c) {
				$ans->{$_} = {%{$q->{$_}}, c => $c};
				$ans->{$_}{ow} = 1 if $ow;
			}
		}
	}
	return $ans;
}
sub remove {
	my ($h, $d) = @_;
	for (keys %$h) {
		my $f = $d . $_;
		my $t = $filetype{$h->{$_}{mode} & 0170000};
		print "$f\n" unless $t;
		if ($t eq "directory")	{ remove($h->{$_}{c}, $f . "/") }
		elsif ($h->{$_}{ow})	{ print "\e[36m", "ignored overwritten file $f.\n", "\e[m" }
		else			{ unlink $f or print "unable to unlink $f.\n" }
	}
	if (rmdir $d)	{ print "successfully rmdir $d.\n" }
	else		{ print "unable to rmdir $d.\n" }
}
sub set {
	my ($f, $mode, $uid, $gid, $mt) = @_;
	# chown should be called before chmod to prevent setuid, setgid bit gets reset.
	chown $uid, $gid, $f and chmod $mode & 07777, $f and cxs::utimensat($f, $mt) or die "$f: $!";
}
sub rf {
	my $f = shift;
	open my $fh, "<", $f or die "open $f for reading: $!";
	return join "", <$fh>;
}
sub wf {
	my ($f, $c) = @_;
	unlink $f or die "$!: unable to remove $f for writing.\n" if -e $f;
	open my $fh, ">", $f or die "open $f for writing: $!";
	if ($c) {
		if (ref $c eq "REF") {
			my $p = $$c;
			cxs::write(fileno($fh), $p->{strref}, $p->{offset}, $p->{length}) or die "cxs::write";
		} else {
			print $fh $c;
		}
		close $fh or die "close $f: $!";
	} else {
		return $fh;
	}
}
sub patch {
	my ($root, $h, $d) = @_;
	$d = "" unless $d;
	for (sort keys %$h) {
		my ($r, $f) = ($d . $_, $root . $d . $_);
		my $t = $filetype{$h->{$_}{mode} & 0170000};
		if ($t eq "directory") {
			unless (-d $f) {
				mkdir $f or die "mkdir $f: $!";
				patch($root, $h->{$_}{c}, $r . "/");
				set($f, @{$h->{$_}}{qw/mode uid gid mt/});
			} else {
				patch($root, $h->{$_}{c}, $r . "/");
			}
		} elsif ($h->{$_}{ow}) {
			print "\e[36m", "ignored overwritten file $f.\n", "\e[m";
		} elsif ($t eq "regular file") {
			if ($h->{$_}{hl}) {
				my $g = $root . $h->{$_}{hl};
				link $g, $f or die "unable to hard link $f to $g: $!";
			} else {
				wf($f, $h->{$_}{c});
				set($f, @{$h->{$_}}{qw/mode uid gid mt/});
			}
		} elsif ($t eq "symbolic link") {
			unlink $f or die "unable to remove $f for symbolic linking.\n" if -e $f;
			symlink $h->{$_}{c}, $f or die "unable to symlink $f to $h->{$_}{c}.";
			my ($uid, $gid, $mt) = @{$h->{$_}}{qw/uid gid mt/};
			# symlink(7) explicitly says the permission of a symbolic link can't be changed(on Linux).
			cxs::lchown($f, $uid, $gid) and cxs::utimensat($f, $mt) or die "$f: $!";
		}
	}
}
sub display {
	my ($h, $d) = @_;
	for (sort keys %$h) {
		my $f = $d . $_;
		my $t = $filetype{$h->{$_}{mode} & 0170000};
		if ($t eq "directory") {
			print "$f/\n";
			display($h->{$_}{c}, $f . "/");
		} else {
			print "\e[36m" if $h->{$_}{ow};
			if ($t eq "symbolic link" or $h->{$_}{hl}) {
				print "$f -> ", $h->{$_}{c}, "\n";
			} elsif ($t eq "regular file") {
				print "$f\n"
			}
			print "\e[m" if $h->{$_}{ow};
		}
	}
}
sub ow0 {
	my ($h, $d) = @_;
	for (sort keys %$h) {
		my $f = $d . $_;
		my $t = $filetype{$h->{$_}{mode} & 0170000};
		if ($t eq "directory") {
			print "$f/\n";
			ow0($h->{$_}{c}, $f . "/");
		} elsif ($h->{$_}{ow}) {
			delete $h->{$_}{ow};
			print "ow flag of $f deleted.\n";
		}
	}
}
sub rs_pson_normalize {
	my $h = shift;
	for (keys %$h) {
		for my $k (keys %{$h->{$_}}) {
			if ($k ne "c") {
				my $p = ${$h->{$_}{$k}};
				$h->{$_}{$k} = substr(${$p->{strref}}, $p->{offset}, $p->{length});
			}
		}
		my $t = $filetype{$h->{$_}{mode} & 0170000};
		if ($t eq "symbolic link" or $h->{$_}{hl}) {
			my $p = ${$h->{$_}{c}};
			$h->{$_}{c} = substr(${$p->{strref}}, $p->{offset}, $p->{length});
		}
		rs_pson_normalize($h->{$_}{c}) if $t eq "directory";
	}
}

my %S;
while (@ARGV) {
	my $s = shift @ARGV;
	if ($s eq "-") {
		last;
	} elsif ($s =~ /^-(.*)/) {
		$s = $1;
		my $p = shift @ARGV;
		if ($p =~ /^-/)	{
			unshift @ARGV, $p;
			$S{$s} = 1;
		} else {
			$S{$s} = $p
		}
	} else {
		unshift @ARGV, $s;
		last
	}
}
my $op = shift @ARGV;
if ($op =~ /compile/) {
	# the source tarball or a directory.
	my $f = shift @ARGV;
	# package name.
	my $pn = $S{package};
	unless ($pn) {
		$f =~ m|([^/]*)-| or die "source tarball filename unrecognized.";
		$pn = $1;
	}
	die "no package name." unless $pn;
	# the directory we want to enter after extracting the tarball.
	my $d;
	if (-d $f) {
		$d = $f;
	} else {
		(c::xsh(1, qw/tar -xvf/, $f))[0] =~ m|([^/\n]*)| or die "tarball structure unable to handle.";
		$d = $1;
	}
	# previous working directory.
	my $pwd = readlink "/proc/self/cwd" or die "readlink: $!.";
	chdir $d or die "chdir $d: $!";
	unless ($B{$pn}{noc}) {
		c::xsh(0, qw/autoreconf -iv/) or die "autoreconf failed." unless -x "configure";
		my $prefix;
		if ($op =~ /^pcompile/) {
			$ENV{CFLAGS} = $ENV{CXXFLAGS} = $ENV{CPPFLAGS} = "-I/p/include";
			unless ($op =~ /32$/)	{ $ENV{LDFLAGS} = "-L/p/lib -L/p/lib64 -Wl,-I/p/lib/ld-linux-x86-64.so.2" }
			else			{ $ENV{LDFLAGS} = "-L/p/lib -Wl,-I/p/lib/ld-linux.so.2" }
			$prefix = "--prefix=/p";
		} else {
			$prefix = "--prefix=/";
		}
		my $e = $B{$pn}{env};
		if ($e) {
			$ENV{$_} = $e->{$_} for (keys %$e);
		}
		c::xsh(0, "./configure", @{$B{$pn}{switch}}, $prefix, qw/r:2>1 | less -KR/) or die "configure failed.";
	}
	c::xsh(0, qw/bash -c/, $B{$pn}{postc}) or die "post configure failed." if $B{$pn}{postc};
	c::xsh(0, "make", @{$B{$pn}{mkparam}}) or die "make failed." unless $B{$pn}{nomk};
	c::xsh(0, qw/rd make install/, @{$B{$pn}{miparam}}) or die "make install failed.";
	c::xsh(0, qw/rd bash -c/, $B{$pn}{postmi}) or die "post make install failed." if $B{$pn}{postmi};
	chdir $pwd or die "chdir to previous working directory $pwd failed: $!.";
	c::xsh(0, qw/echo rm -rf/, $d) or die "cannot remove source code directory." unless -d $f;
} elsif ($op =~ /^(display|\+ow|delete|add|remove|patch|check)$/) {
	my $f = shift @ARGV;
	cxs::mmap($f, my $b);
	my $h = (pson_parse({strref => \$b, flag => 1}, 0))[0];
	rs_pson_normalize($h);
	if ($op eq "display") {
		display($h, "");
	} elsif ($op eq "+ow") {
		ow0($h, "");
		pson_unparse_w($h, wf($f));
	} elsif ($op eq "delete") {
		# flag indicate the if we made any change.
		my $c = 0;
		for (@ARGV) {
			my @d = split m|/|;
			my ($i, $p) = (0, $h);
			while ($i < @d - 1) {
				$p = $p->{$d[$i]}{c};
				last unless $p;
				$i++;
			}
			if ($p and $p->{$d[$i]}) {
				delete $p->{$d[$i]}, $c = 1;
				print "successfully deleted $_.\n";
			} else {
				print "$_ not found.\n";
			}
		}
		pson_unparse_w($h, wf($f)) if $c;
	} elsif ($op eq "add") {
		# how many prefix / are going to be removed.
		my $p = 1;
		for (@ARGV) {
			$p = $1, next if /^-p(\d+)$/;
			pos = 0;
			my ($i, $c) = ($p, "");
			$i--, $c .= $1 while $i and m|(.*?/)|gc;
			print "prefix $c of $_ removed.\n";
			my $g = $h;
			while (m|(.*?)/|gc) {
				$c .= $1 . "/";
				unless ($g->{$1}) {
					$g->{$1} = {c => {}};
					@{$g->{$1}}{qw/mode uid gid mt/} = (lstat($c))[2, 4, 5, 9];
				}
				$g = $g->{$1}{c};
			}
			/(.*)/g;
			if ($1) {
				print "adding file ", $c . $1, ".\n";
				$g->{$1} = {};
				@{$g->{$1}}{qw/mode uid gid mt/} = (lstat($c . $1))[2, 4, 5, 9];
				my $t = $filetype{$g->{$1}{mode} & 0170000};
				if ($t eq "regular file") {
					my $h = {
						type => "mmap",
						f => $c . $1
					};
					$g->{$1}{c} = \$h;
				} elsif ($t eq "symbolic link") {
					$g->{$1}{c} = readlink $c . $1 or die $!;
				} else {
					die "filetype of ", $c . $1, " unrecognized.\n";
				}
			} else {
				print "adding directory $c.\n";
				my $d = walk({root => $c, exclude => [], ih => {}});
				%$g = %{diff({}, $d, $c)};
			}
		}
		pson_unparse_w($h, wf($f));
	} else {
		# remove or patch now.
		my $root = shift @ARGV;
		die "root directory not specified." unless $root;
		if ($op eq "remove") {
			remove($h, $root)
		} elsif ($op eq "check") {
			my $d = check({root => $root, ih => {}}, $h);
			if (%$d) {
				display($d, $root)
			} else {
				print "\e[32mperfect\e[m.\n"
			}
		} else {
			my $g = {};
			for (@ARGV) {
				my @d = split m|/|;
				my ($i, $p, $q) = (0, $h, $g);
				while ($i < @d - 1) {
					$p = $p->{$d[$i]};
					die "$_ doesn't exist in $f." unless $p;
					unless ($q->{$d[$i]}) {
						$q = $q->{$d[$i]} = {c => {}};
						for (keys %$p) {
							$q->{$_} = $p->{$_} if $_ ne "c";
						}
					} else {
						$q = $q->{$d[$i]};
					}
					$p = $p->{c}, $q = $q->{c};
					$i++;
				}
				$q->{$d[$i]} = $p->{$d[$i]} or die "$_ doesn't exist in $f.";
			}
			patch($root, %$g ? $g : $h);
		}
	}
} else {
	my ($root, $df) = @ARGV;
	die "root directory not specified." unless $root;
	my $p = {
		root => $root,
		ih => {},
		exclude => [
			qw/lost+found home var root boot proc sys run dev tmp p usr private/,
			#   these two info directory files are updated when installing info files, they don't
			# really belong to any particular package.
			"info/dir", "share/info/dir",
			#   system-wide configuration files that we mannually edited, we don't want any package
			# to claim anyone of them as its contents, or if we remove such a package in order to
			# update, they will be deleted.
			map("etc/" . $_,
			    qw|
				passwd group shadow hosts init0 init1 inittab keymaps.rc lynx.cfg
				lynx.lss mtab nsswitch.conf protocols resolv.conf udev/rules.d
				X11/xorg.conf wgetrc login.defs fstab ld.so.cache sshd.pid ld.so.conf
				services smb.conf sshd_config hosts.allow hosts.deny exports adjtime
				modprobe.d

				passwd- group- shadow-
			    |,
			),
			#   temporary symbolic links, should be commented out when the package they belong to is
			# installed.
			#"lib/ld-linux.so.2",
			#"bin/sh", "bin/bash",
			#"bin/pwd",
			#"bin/perl",
			#   interpreter for x86-64 is expected in /lib64, but glibc doesn't automatically create
			# the symbolic link for us.
			"lib64/ld-linux-x86-64.so.2",
			# INPUT(-lncursesw)
			"lib/libncurses.so",
			# symbolic link to include/ncursesw
			"include/ncurses",
			#   mannually edited, since ncurses is installed before pkgconfig, we can avoid supplying
			# additional flags to quite a few packages after.
			map("lib/pkgconfig/" . $_, qw/ncurses.pc ncursesw.pc/),
			# ssl related.
			map("ssl/" . $_, qw/openssl.cnf certs cert.pem/),
			# kernel modules.
			"lib/modules",
			# windows fonts.
			"share/fonts/X11/windows",
			# dejavu fonts.
			"share/fonts/X11/dejavu",
			# downloaded from http://www.linux-usb.org/usb-ids.html.
			"share/usb.ids"
		    ]
	};
	if ($op eq "create") {
		my $h = walk($p);
		wf(".rs", c::json_unparse($h));
	} else {
		die "diff file not specified." unless $df;
		if ($op eq "diff") {
			my $q = walk($p);
			my $p = c::json_parse_wrap(rf(".rs"));
			pson_unparse_w(diff($p, $q, $root), wf($df));
		}
	}
}
print rf("/proc/self/status") if $S{verbose};
