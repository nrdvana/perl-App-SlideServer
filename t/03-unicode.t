#!perl
use v5.36;
use utf8;
use Test::More;
use Test::Mojo;
use File::Temp;
use App::SlideServer;

my $nanika= chr(0x4F55).chr(0x304B);

subtest html => sub {
	my $html= <<~HTML;
		<html>
		<head><title>Test1</title></head>
		<body><div class="slides">
			<div class="slide">
				<h2>$nanika</h2>
			</div>
		</div></body>
		</html>
		HTML
	my $f= File::Temp->new;
	binmode($f, ':encoding(UTF-8)');
	$f->print($html);
	$f->seek(0,0);
	
	for my $ss (
		App::SlideServer->new(slides_source_file => \$html),
		App::SlideServer->new(slides_source_file => "$f"),
		#App::SlideServer->new(slides_source_file => $f),
	) {
		like( $ss->load_slides_html, qr/$nanika/, 'contains high chars' );
		my $slides= $ss->slides_dom;
		is( scalar @$slides, 1, 'one slide built' )
			or diag explain $slides;
		like( "$slides->[0]", qr|<h2>$nanika</h2>|, 'slide contains expected heading' );
	}
};

done_testing;
