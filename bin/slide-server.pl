#! /usr/bin/env perl
use v5.36;
use FindBin;
use Cwd;
use Mojo::File 'path';
use Log::Any::Adapter 'Daemontools', -init => { argv => 1, env => 1 };

# in case running in Docker, need signal handlers installed
$SIG{INT}= $SIG{TERM}= sub { exit 0; };

my %opts= (
	serve_dir => path($ENV{APP_DATA_PATH} || Cwd::getcwd()),
);
$opts{share_dir}= path($ENV{APP_SHARE_DIR}) if length ($ENV{APP_SHARE_DIR} // '');
$opts{presenter_key}= $ENV{PRESENTER_KEY} if length ($ENV{PRESENTER_KEY} // '');

# Allow running from project dir
push @INC, "$FindBin::RealBin/../lib"
	if -f "$FindBin::RealBin/../lib/App/SlideServer.pm";

require App::SlideServer;
my $app= App::SlideServer->new(\%opts);

push @ARGV, qw( daemon -l http://*:2000 ) unless @ARGV;
$app->start(@ARGV);
