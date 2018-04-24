use App::rs 'sane', 'iautoload' => [['Test', map { "0$_" } qw/plan ok/]];

plan tests => 1;
ok 1;
