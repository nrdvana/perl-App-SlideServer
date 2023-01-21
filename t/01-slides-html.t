#!perl
use v5.36;
use Test2::V0;
use Test::Mojo;

my $t= Test::Mojo->new('App::SlideServer');
# use the example slides.html as the user's content
$t->app->serve_dir($t->app->share_dir);

$t->get_ok('/')
	->status_is(200)
	->content_like(qr,<h1[^>]*>Slide 1</h1>,ms);

done_testing;
