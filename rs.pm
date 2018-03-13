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
package App::rs;
use strict;
use warnings qw/all FATAL uninitialized/;
use feature qw/state say/;

use XSLoader;
XSLoader::load();

BEGIN {
	my $c = {S_IFMT => 0170000,
		 S_IFLNK => 0120000,
		 S_IFREG => 0100000,
		 S_IFDIR => 0040000};
	my @H = ($^H, ${^WARNING_BITS}, %^H);
	sub import {
		no strict 'refs';
		my $ns = caller . '::';
		shift;
		while (@_) {
			my $q = shift;
			if ($q eq 'iautoload') {
				my (@pkg, %map);
				for (@{+shift}) {
					my ($p, @f) = ref $_ ? @$_ : $_;
					push @pkg, $p;
					$map{$_} = $p for @f;
				}
				*{$ns . 'AUTOLOAD'} = sub {
					# "fully qualified name of the original subroutine".
					my $q = our $AUTOLOAD;
					# to avoid possibly overwrite @_ by successful regular expression match.
					my ($f) = do { $q =~ /.*::(.*)/ };
					no strict 'refs';
					for my $p ($map{$f} || @pkg) {
						#   calculate the actual file to be loaded thus avoid eval and
						# checking $@ mannually.
						do { require $p =~ s|::|/|gr . '.pm' };
						if (my $r = *{"${p}::$f"}{CODE}) {
							*$q = $r;
							# TODO: understand why using goto will lost context.
							#goto &$r;
							return &$r;
						}
					}
					confess("unable to autoload $q.");
				};
			} elsif ($q eq 'oautoload') {
				for my $p (@{+shift}) {
					my $r = $p =~ s|::|/|gr . '.pm';
					# ignore already loaded module.
					next if $INC{$r};
					*{"${p}::AUTOLOAD"} = sub {
						my ($f) = do { our $AUTOLOAD =~ /.*::(.*)/ };
						my $symtab = *{"${p}::"}{HASH};
						delete $symtab->{AUTOLOAD};
						require $r;
						return &{$symtab->{$f}};
					};
				}
			} elsif ($q eq 'constant') {
				*{$ns . $_} = \&$_ for keys %$c;
			} elsif ($q eq 'sane') {
				($^H, ${^WARNING_BITS}, %^H) = @H;
			} else {
				confess("unknown request $q");
			}
		}
	};
	for my $f (keys %$c) {
		my $v = $c->{$f};
		no strict 'refs';
		*$f = sub () {
			$v;
		};
	}
}
{my @a = qw/Cpanel::JSON::XS JSON::XS JSON::PP/;
 App::rs->import(iautoload => ['Carp'],
		 oautoload => [@a]);
 sub json_unparse_readable {
	 state $o = do {
		 my $o;
		 for (@a) {
			 last if eval {
				 $o = $_->new->pretty->canonical;
			 };
		 }
		 $o;
	 };
	 $o ? $o->encode(shift) : "what?!\n";
 }}
sub xsh {
	my $f = shift;
	if (not ref $f) {
		my $h = {};
		$h->{"capture-stdout"} = 1 if $f & 1;
		$h->{"feed-stdin"} = 1 if $f & 2;
		$f = $h;
	}
	my ($h, $i, $pr, @st) = ({pid => []}, 0);
	if ($f->{"feed-stdin"}) {
		my ($fi, $pid) = shift;
		pipe $pr, my $pw;
		if (not $pid = fork) {
			close $pr;
			print $pw $fi;
			exit;
		} else {
			push @{$h->{pid}}, $pid;
		}
	}
	while ($i <= @_) {
		my $l = $i == @_;
		my $a = $_[$i] if not $l;
		if ($l or $a eq "|") {
			pipe my $r, my $w if not $l or $f->{"capture-stdout"};
			# there's no need to fork when executing the last command and we're required
			# to substitute current process.
			my $pid = fork unless $l and $f->{substitute};
			if (not $pid) {
				# always true except possibly the first.
				open STDIN, "<&", $pr if $pr;
				# always true except possibly the last.
				open STDOUT, ">&", $w if $w;
				while (ref $st[-1]) {
					my ($h, $f) = pop @st;
					if (ref \$h->{from} eq "SCALAR")	{ open $f, $h->{mode}, $h->{from} or die $! }
					else					{ $f = $h->{from} }
					open $h->{to}, $h->{mode} . "&", $f;
				}
				exec @st;
			} else {
				$pr = $r;
				push @{$h->{pid}}, $pid;
				@st = ();
			}
		} else {
			push @st, $a;
		}
		$i++;
	}
	if ($f->{asynchronous}) {
		$h->{stdout} = $pr if $f->{"capture-stdout"};
		if ($f->{compact})		{ $h }
		elsif ($f->{"capture-stdout"})	{ $pr }
		else				{ wantarray ? @{$h->{pid}} : $h->{pid}[-1] }
	} else {
		if ($f->{"capture-stdout"}) {
			local $/ if not wantarray;
			$h->{stdout} = [<$pr>];
		}
		$h->{status} = [];
		push @{$h->{status}}, waitpid($_, 0) == -1 ? undef : $? for @{$h->{pid}};
		# they're meaningless now as they don't exist anymore.
		delete $h->{pid};
		if ($f->{compact})		{ $h }
		elsif ($f->{"capture-stdout"})	{ wantarray ? @{$h->{stdout}} : $h->{stdout}[0] }
		else				{ wantarray ? @{$h->{status}} : not $h->{status}[-1] }
	}
}
sub arg_parse {
	my $h = {};
	while (@ARGV) {
		my $a = shift @ARGV;
		if ($a !~ /^-/)			{ unshift @ARGV, $a; last }
		elsif ($a =~ /^--?$/)		{ last }
		elsif ($a =~ /^--(.*?)=(.*)$/)	{ hash_madd_key($h, $1, $2) }
		elsif ($a =~ /^--?(.*)$/)	{ $h->{$1} = 1 }
	}
	$h;
}
sub hash_madd_key {
	my ($h, $k, $v) = @_;
	if (exists $h->{$k}) {
		$h->{$k} = [$h->{$k}] if ref $h->{$k} ne 'ARRAY';
		push @{$h->{$k}}, $v;
	} else {
		$h->{$k} = $v;
	}
}
sub flatten {
	my $v = shift;
	ref $v eq 'ARRAY' ? @$v : $v;
}
1;
