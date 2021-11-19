=license

	Copyright © 2018,2021 Yang Bo

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
require v5.14;
require Devel::PPPort;
Devel::PPPort::WriteFile();
require ExtUtils::MakeMaker;
*WriteMakefile = \&ExtUtils::MakeMaker::WriteMakefile;
my $me = '://github.com/057a3dd61f99517a3afea0051a49cb27994f94d/rslinux';

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
my $s = arg_parse();
my $fuse = not $s->{'no-fuse'};

WriteMakefile(NAME => 'App::rs',
	      ABSTRACT_FROM => 'bin/rs',
	      AUTHOR => ['Yang Bo <rslovers@yandex.com>'],
	      EXE_FILES => ['bin/rs'],
	      MAN3PODS => {},
	      VERSION_FROM => 'rs.pm',
	      META_MERGE => {resources => {repository => {type => 'git',
							  url => "git$me.git",
							  web => "https$me"},
					   homepage => "https$me",
					   bugtracker => {web => "https$me/issues"}},
			     'meta-spec' => {version => 2}},
	      LD => 'g++',
	      OBJECT => ['rs.o', $fuse ? 'fuse.o' : ()],
	      INC => '-I/include/fuse3 -I../mp -I.',
	      dynamic_lib => {OTHERLDFLAGS => $fuse ? '-lfuse3 -lpthread' : ''},
	      LICENSE => 'gpl_3');
