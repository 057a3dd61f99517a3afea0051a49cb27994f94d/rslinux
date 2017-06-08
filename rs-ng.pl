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
use strict;
use c;
use feature qw/say state/;
our @A = qw/c cxs/;

main();

sub rs_parse_wrap {
	my $f = shift;
	my $cp = {b => undef,
		  p => 0};
	mmap($f, $cp->{b});
	rs_parse($cp);
}
sub rs_parse {
	my ($cp, $vp) = @_;
	my ($k, $t, $l, $v) = ($vp->{k} // "",
			       substr($cp->{b}, $cp->{p}, 1),
			       unpack "L", substr $cp->{b}, $cp->{p}+1, 4);
	$cp->{p} += 5;
	if ($t eq "S") {
		if ($k eq "c") {
			$v = {s => \$cp->{b},
			      l => $l,
			      o => $cp->{p}};
		} else {
			$v = substr $cp->{b}, $cp->{p}, $l;
		}
		$cp->{p} += $l;
	} else {
		$v = {};
		while ($l--) {
			my $k = rs_parse($cp);
			$v->{$k} = rs_parse($cp, {k => $k});
		}
	}
	$v;
}
sub rs_unparse {
	my ($cp, $vp) = @_;
	my ($v, $k) = ($vp->{v}, $vp->{k} // "");
	if ($k eq "c" and (not ref $v or ref $v->{s} eq "SCALAR")) {
		if (ref $v) {
			syswrite $cp->{sink}, "S" . pack "L", $v->{l};
			syswrite $cp->{sink}, ${$v->{s}}, $v->{l}, $v->{o};
		} else {
			if (mmap($v, my $b)) {
				syswrite $cp->{sink}, "S" . pack "L", length $b;
				syswrite $cp->{sink}, $b;
				munmap($b, length $b);
			} else {
				syswrite $cp->{sink}, "S" . pack "L", 0;
			}
		}
	} else {
		if (not ref $vp->{v}) {
			syswrite $cp->{sink}, "S" . pack("L", length $v) . $v;
		} else {
			syswrite $cp->{sink}, "H" . pack "L", ~~keys %$v;
			for (keys %$v) {
				rs_unparse($cp, {v => $_});
				rs_unparse($cp, {v => $v->{$_},
						 k => $_});
			}
		}
	}
}
sub set {
	my ($f, $mode, $uid, $gid, $mtime) = @_;
	# chown should be called before chmod to prevent setuid, setgid bit gets reset.
	chown $uid, $gid, $f and chmod $mode & 07777, $f and utimensat($f, $mtime) or die "$f: $!";
}
sub equiv {
	my ($p, $q) = @_;
	my $f = 1;
	for (qw/mode uid gid size mtime hl sl/) {
		$f = 0, last if ($p->{$_} // "") ne ($q->{$_} // "");
	}
	$f;
}
sub elf {
	my ($f, $v) = shift;
	mmap($f, my $b);
	$v = 1 if length $b >= 4 and substr($b, 0, 4) eq "\x7fELF";
	munmap($b, length $b);
	$v;
}
sub strip {
	my ($f, $m, $root) = @_;
	my $s = {};
	if (/\.[ao]$/)						{ @$s{qw/strip archive/} = (1, 1) }
	elsif ((/\.so/ or $m->{mode} & 0111) and elf($f))	{ $s->{strip} = 1 }
	if ($s->{strip}) {
		xsh(0, "strip", $s->{archive} ? "--strip-unneeded" : (), $f);
		say "strip on $f, st: $?.";
		if (not $?) {
			set($f, @$m{qw/mode uid gid mtime/});
			$m->{size} = (stat $f)[7];
		}
	}
}
sub diff {
	my ($cp, $vp) = @_;
	my ($db, $v) = ($vp->{db}, {});
	opendir(my $dh, $cp->{root} . $vp->{d}) or die $!;
	for (sort readdir $dh) {
		my $ign = $vp->{ign}{$_};
		# ignore leaf only.
		next if /^\.{1,2}$/ or $ign and not ref $ign;
		my ($r, $f, $m) = ($vp->{d} . $_, $cp->{root} . $vp->{d} . $_, {});
		(my $i, @$m{qw/mode uid gid size mtime/}) = (lstat $f)[1, 2, 4, 5, 7, 9];
		if ($cp->{ih}{$i})	{ $m->{hl} = $cp->{ih}{$i} }
		else			{ $cp->{ih}{$i} = $r }
		my $t = $m->{mode} & S_IFMT;
		if ($t == S_IFDIR)	{ delete $m->{size} }
		elsif ($t == S_IFLNK)	{ $m->{sl} = readlink $f or die $! }
		elsif ($t != S_IFREG)	{ die "unknown type $t of $f." }
		my $st = {};
		if (my $_m = $db->{$_}) {
			my $_t = $_m->{mode} & S_IFMT;
			if ($t == S_IFDIR xor $_t == S_IFDIR)	{ ... }
			elsif ($t == S_IFDIR)			{ $st->{dir} = 1 }
			else					{ $st->{mod} = 1 if not equiv($m, $_m) }
		} else {
			$st->{ne} = 1;
		}
		if (%$st) {
			if ($t == S_IFDIR) {
				my $p = $db->{$_} = {%$m,
						     c => $db->{$_}{c},
						     owner => $db->{$_}{owner}};
				$p->{c} = {} if not $p->{c};
				my $c = diff($cp, {db => $p->{c},
						   ign => $vp->{ign}{$_},
						   d => $r . "/"});
				if ($st->{ne} or %$c) {
					$v->{$_} = {%$m,
						    c => $c};
					$p->{owner}{$cp->{oid}} = $cp->{ts};
				}
			} else {
				my $n = 1 if $t == S_IFREG and not $m->{hl};
				strip($f, $m) if $n;
				my $p = $db->{$_} = {%$m,
						     owner => $db->{$_}{owner}};
				$p->{owner}{current} = $cp->{oid}, $p->{owner}{record}{$cp->{oid}} = $cp->{ts};
				$v->{$_} = {%$m};
				$v->{$_}{c} = $f if $n;
			}
		}
	}
	$v;
}
sub patch {
	my ($cp, $vp) = @_;
	my ($db, $v) = @$vp{qw/db v/};
	for (sort keys %$v) {
		my ($r, $f, $q) = ($vp->{d} . $_, $cp->{root} . $vp->{d} . $_, $v->{$_});
		#my $t = $q->{mode} & S_IFMT;
		my $t = $q->{sl} ? S_IFLNK : $q->{mode} & S_IFMT;
		if ($t == S_IFDIR) {
			if (not $db->{$_}) {
				mkdir $f or die "mkdir $f: $!";
				$db->{$_} = {%$q,
					     c => {}};
			}
			my $p = $db->{$_};
			patch($cp, {v => $q->{c},
				    db => $p->{c},
				    d => $r . "/"});
			set($f, @$p{qw/mode uid gid mtime/}) if not $p->{owner};
			$p->{owner}{$cp->{oid}} = $cp->{ts};
		} else {
			my $p = $db->{$_} = {%$q,
					     owner => $db->{$_}{owner}};
			unlink $f or die "$f exists but unable to unlink." if -e $f;
			if ($t == S_IFREG) {
				if ($p->{hl}) {
					my $g = $cp->{root} . $p->{hl};
					link $g, $f or die "unable to hard link $f to $g: $!";
				} else {
					wf($f, delete $p->{c});
					set($f, @$p{qw/mode uid gid mtime/});
				}
			} else {
				#unlink $f or die "unable to remove $f for symbolic linking.\n" if -e $f;
				symlink $p->{sl}, $f or die "unable to symlink $f to $p->{sl}: $!.";
				# symlink(7) explicitly says the permission of a symbolic link can't be changed(on Linux).
				lchown($f, @$p{qw/uid gid/}) and utimensat($f, $p->{mtime}) or die "$f: $!";
			}
			$p->{owner}{current} = $cp->{oid}, $p->{owner}{record}{$cp->{oid}} = $cp->{ts};
		}
	}
}
# merge two patch trees, the first one takes higher priority.
sub merge {
	my ($p, $q) = @_;
	for (keys %$q) {
		if (not $p->{$_}) {
			$p->{$_} = $q->{$_};
		} else {
			my ($t, $_t) = ($p->{$_}{mode} & S_IFMT, $q->{$_}{mode} & S_IFMT);
			if ($t == S_IFDIR xor $_t == S_IFDIR)	{ ... }
			elsif ($t == S_IFDIR)			{ merge($p->{$_}{c}, $q->{$_}{c}) }
		}
	}
}
# add path r from v to p.
sub grow {
	my ($p, $v, $r) = @_;
	my @d = split m|/|, $r;
	my $f = pop @d;
	for (@d) {
		$p->{$_} = {%{$v->{$_}},
			    c => {}} if not $p->{$_};
		$p = $p->{$_}{c}, $v = $v->{$_}{c};
	}
	$p->{$f} = $v->{$f};
}
sub rm {
	my ($cp, $vp) = @_;
	my $db = $vp->{db};
	for (keys %$db) {
		my ($r, $f, $p, $o) = ($vp->{d} . $_, $cp->{root} . $vp->{d} . $_, $db->{$_}, $db->{$_}{owner});
		if ($p->{c}) {
			if ($o->{$cp->{oid}}) {
				rm($cp, {db => $p->{c},
					 d => $r . "/"});
				delete $o->{$cp->{oid}};
				if (not %$o) {
					rmdir $f or die "unable to rmdir $f: $!.";
					delete $db->{$_};
				}
			}
		} else {
			if ($o->{record}{$cp->{oid}}) {
				delete $o->{record}{$cp->{oid}};
				if ($o->{current} eq $cp->{oid}) {
					unlink $f or warn "unable to unlink $f: $!.";
					if (%{$o->{record}}) {
						my $oid;
						for (keys %{$o->{record}}) {
							$oid = $_ if not $oid or $o->{record}{$_} > $o->{record}{$oid};
						}
						my $p = $cp->{patch};
						if (not $p->{$oid}) {
							my $v = rs_parse_wrap($cp->{pool} . $oid . ".rs");
							$p->{$oid} = {v => $v,
								      p => {}};
						}
						grow(@{$p->{$oid}}{qw/p v/}, $r);
					} else {
						delete $db->{$_};
					}
				}
			}
		}
	}
}
sub wf {
	my ($f, $c) = @_;
	unlink $f or die "$!: unable to remove $f for writing.\n" if -e $f;
	open my $fh, ">", $f or die "open $f for writing: $!";
	if ($c) {
		if (ref $c eq "HASH") {
			syswrite $fh, ${$c->{s}}, $c->{l}, $c->{o};
		} else {
			print $fh $c;
		}
		close $fh or die "close $f: $!";
	} else {
		return $fh;
	}
}
sub priv {
	my $f = shift;
	my ($uid, $gid) = (getpwnam $ENV{USER})[2, 3];
	if (not $f) {
		($(, $)) = ($gid, "$gid $gid");
		setresuid($uid, $uid, 0);
	} else {
		setresuid(0, 0, 0);
		($(, $)) = (0, "0 0");
	}
}
sub tag {
	my ($cp, $vp) = @_;
	my ($v, $oid, $db, $d) = ({}, $cp->{oid}, @$vp{qw/db d/});
	say {$cp->{sink}} $d;
	for (keys %$db) {
		my ($p, $r) = ($db->{$_}, $d . $_);
		if ($p->{c}) {
			$v->{$_} = {%$p,
				    c => tag($cp, {db => $p->{c},
						   d => $r . "/"})} if $p->{owner}{$oid};
		} else {
			$v->{$_} = $p, say {$cp->{sink}} $r if $p->{owner}{record}{$oid};
		}
	}
	$v;
}
sub main {
	my $p = do "$ENV{HOME}/.rs.profile" // {};
	while (@ARGV) {
		my $s = arg_parse();
		$p = do $s->{profile} if $s->{profile};
		$s = {%$p,
		      %$s};
		my $op = shift @ARGV;
		my $db = rs_parse_wrap($s->{db}) if $op =~ /^(diff|patch|rm|tag)$/;
		if ($op eq "diff") {
			my ($oid, $root) = splice @ARGV, 0, 2;
			my ($p, $_v) = $s->{pool} . $oid . ".rs";
			if (-e $p) {
				say "$p exists, will merge with new generated patch tree.";
				$_v = rs_parse_wrap($p);
			}
			my $v = diff({ih => {},
				      root => $root,
				      oid => $oid,
				      ts => time}, {db => $db,
						    ign => $s->{ign} ? do $s->{ign} : undef,
						    d => ""});
			merge($v, $_v) if $_v;
			rs_unparse({sink => wf($p)}, {v => $v});
		} elsif ($op eq 'patch') {
			my ($f, $root) = splice @ARGV, 0, 2;
			#   v is the parsed value of the patch, and can be cut using subtree switch,
			# the final patch to apply is stored in p.
			my $v = my $p = rs_parse_wrap($f);
			if (exists $s->{subtree}) {
				$p = {};
				grow($p, $v, $_) for flatten($s->{subtree});
			}
			my ($oid) = $f =~ m|([^/]*).rs$|;
			patch({root => $root,
			       oid => $oid,
			       ts => time}, {v => $p,
					     db => $db,
					     d => ''});
		} elsif ($op eq "rm") {
			my ($oid, $root) = splice @ARGV, 0, 2;
			rm({root => $root,
			    oid => $oid,
			    pool => $s->{pool},
			    patch => my $p = {}}, {db => $db,
						   d => ""});
			my $ts = time;
			for (keys %$p) {
				patch({root => $root,
				       oid => $_,
				       ts => $ts}, {v => $p->{$_}{p},
						    db => $db,
						    d => ""});
			}
		} elsif ($op eq "compile") {
			# drop root privilege before compile, as suggested by many packages.
			priv(0);
			my ($p, $oid, $pkg, $d) = shift @ARGV;
			if (-d $p) {
				$oid = $s->{oid} or die "oid not specified for $p.";
				$d = $p;
			} else {
				($oid) = $p =~ m|([^/]*).tar.*$|;
				($d) = (xsh(1, qw/tar -xvf/, $p))[0] =~ m|([^/\n]*)| or die "bad tarball.";
			}
			($pkg) = $oid =~ m|(.*)-|;
			my $_d = readlink '/proc/self/cwd' or die "readlink: $!.";
			chdir $d or die "chdir $d: $!.";
			my $b = (do $s->{build})->{$pkg};
			xsh({'feed-stdin' => 1}, $b->{'pre-configure'}, 'bash') or die 'pre-configure failed.' if $b->{'pre-configure'};
			unless ($b->{'no-configure'}) {
				local %ENV = %ENV;
				xsh(0, qw/autoreconf -iv/) or die "autoreconf failed." unless -e 'configure';
				my @p;
				if ($s->{bootstrap}) {
					$ENV{CPPFLAGS} = "-I/p/include" unless $b->{'no-cppflags'};
					$ENV{LDFLAGS} = '-L/p/lib -Wl,-I' . ($s->{i386} ?
									     '/p/lib/ld-linux.so.2' : $s->{arm} ?
									     '/p/lib/ld-linux-armhf.so.3' :
									     '/p/lib/ld-linux-x86-64.so.2');
					push @p, "--prefix=/p";
				} else {
					push @p, "--prefix=/usr";
				}
				my $e = $b->{environment};
				$ENV{$_} = $e->{$_} for keys %$e;
				xsh(0, "./configure", @{$b->{switch}}, @p,
				    {to => *STDERR,
				     from => *STDOUT,
				     mode => ">"}, qw/| less -KR/) or die "configure failed.";
			}
			xsh({'feed-stdin' => 1}, $b->{'post-configure'}, 'bash') or die 'post-configure failed.' if $b->{'post-configure'};
			xsh(0, 'make', $s->{jobs} ? "--jobs=$s->{jobs}" : (), @{$b->{'make-parameter'}}) or die 'make failed.' unless $b->{'no-make'};
			xsh({'feed-stdin' => 1}, $b->{'post-make'}, 'bash') or die 'post-make failed.' if $b->{'post-make'};
			priv(1);
			xsh(0, qw/make install/, @{$b->{'make-install-parameter'}}) or die 'make install failed.';
			xsh({'feed-stdin' => 1}, $b->{'post-make-install'}, 'bash') or die 'post-make failed.' if $b->{'post-make-install'};
			xsh(0, qw/git clean -fdx/) if $s->{oid};
			chdir $_d or die "chdir $_d: $!.";
			# remove uncompressed tarball.
			xsh(0, qw/rm -rf/, $d) if not $s->{oid};
			push @ARGV,
			"diff", $oid, $s->{bootstrap} ? "/p/" : "/",
			"tag", $oid;
		} elsif ($op eq 'tag') {
			my $oid = shift @ARGV;
			pipe my $r, my $w or die $!;
			my $pid = xsh({asynchronous => 1}, qw/less -R/, {to => *STDIN,
									 from => $r,
									 mode => "<"});
			_json_unparse({readable => 1,
				       sink => $w}, {v => tag({oid => $oid,
							       sink => $w}, {db => $db,
									     d => ""}),
						     d => 0});
			close $w;
			# we must wait here or we will lose control-terminal.
			waitpid $pid, 0;
		}
		rs_unparse({sink => wf($s->{db})}, {v => $db}) if $op =~ /^(diff|patch|rm)$/;
	}
}
