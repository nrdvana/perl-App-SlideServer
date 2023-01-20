#! /usr/bin/env perl
use v5.36;
use FindBin;
use Mojolicious::Lite;
use Mojo::WebSocket 'WS_PING';
use Mojo::File 'path';
use Mojo::DOM;
use Log::Any '$log';
use Log::Any::Adapter 'Daemontools', -init => { argv => 1, env => 1 };
use Text::Markdown::Hoedown;

$SIG{INT}= $SIG{TERM}= sub { exit 0; };

our $APPDIR= $ENV{APPDIR} // $FindBin::RealBin;

our $presenter_key= $ENV{PRESENTER_KEY}
	or die "Missing env PRESENTER_KEY";
my ($markdown_source)= grep -f $_, "$APPDIR/slides.md", "$APPDIR/public/slides.md";
my ($html_source)= grep -f $_, "$APPDIR/slides.html", "$APPDIR/public/slides.html";
defined $markdown_source or defined $html_source
	or die "Require one of slides.md or slides.html";

sub markdown_to_html {
	markdown(shift, extensions => (
		HOEDOWN_EXT_TABLES | HOEDOWN_EXT_FENCED_CODE | HOEDOWN_EXT_AUTOLINK | HOEDOWN_EXT_STRIKETHROUGH
		| HOEDOWN_EXT_UNDERLINE | HOEDOWN_EXT_QUOTE | HOEDOWN_EXT_SUPERSCRIPT | HOEDOWN_EXT_NO_INTRA_EMPHASIS
		| HOEDOWN_EXT_DISABLE_INDENTED_CODE
		)
	);
}

# This function takes partial HTML (or full HTML) and upgrades it to full HTML
# with the needed css and js for the slides.
sub generate_slides_html {
	my $custom= Mojo::DOM->new(shift);
	my $result= Mojo::DOM->new(path("$APPDIR/slides_example.html")->slurp);
	# Remove the example slides
	$result->at('body')->replace('<body></body>');
	# If custom defines a <head>, merge its elements into the example
	# TODO: prevent redundant header elements
	$result->at('head')->append_content($custom->at('head')->child_nodes)
		if $custom->at('head');
	$result->at('body')->append_content('<div class="slides"></div>');
	my $slides= $result->at('div.slides');
	# Find each custom element that is an immediate child of body, and add it to
	# the current slide until the next <h1> <h2> or <div class="slide"> at which
	# point, move to the next slide.
	my $cur_slide;
	for (($custom->at('div.slides') || $custom->at('body') || $custom)->@*) {
		my $tag= lc($_->tag // '');
		# is it a whole pre-defined slide
		if ($tag eq 'div' && $_->{class} =~ /\bslide\b/) {
			$cur_slide= undef;
			$slides->append_content($_);
		}
		else {
			# start a new slide every time H1 or H2 seen
			$cur_slide= undef if $tag eq 'h1' || $tag eq 'h2';
			# Add "auto-step" to any <UL> tags
			$_->{class}= "auto-step" if ($tag eq 'ul' || $tag eq 'ol') && !$_->{class};
			$cur_slide //= do {
				$slides->append_content('<div class="slide"></div>');
				$slides->children('div.slide')->last;
			};
			$cur_slide->append_content($_);
		}
	}
	return "$result";
}

get '/' => sub ($c, @) {
	my $html= $markdown_source? markdown_to_html(path($markdown_source)->slurp)
		: path($html_source)->slurp;
	$c->render(text => generate_slides_html($html));
};

my $cur_extern= '';
my %viewers;
my %published_state;

sub update_published_state {
	%published_state= ( %published_state, @_ );
	$_->send({ json => { state => \%published_state } }) for values %viewers;
}

websocket '/slidelink.io' => sub {
	my $c= shift;
	my $id= $c->req->request_id;
	$viewers{$id}= $c;
	my $mode= $c->req->param('mode');
	my $key= $c->req->param('key');
	my %roles= (follow => 1);
	if ($mode == 'presenter') {
		if (($key||'') eq $presenter_key) {
			$roles{lead}= 1;
			update_published_state(viewer_count => scalar keys %viewers);
		}
	}
	$c->stash('roles', join ',', keys %roles);
	$log->infof("%s (%s) connected as %s", $id, $c->tx->remote_address, $c->stash('roles'));
	$c->send({ json => { roles => [ keys %roles ] } });
	
	$c->on(json => sub {
		my ($c, $msg)= @_;
		$log->debugf("client %s %s msg=%s", $id, $c->tx->original_remote_address, $msg) if $log->is_debug;
		if ($c->stash('roles') =~ /\blead\b/) {
			if (defined $msg->{extern}) {
			}
			if (defined $msg->{slide_num}) {
				update_published_state(slide_num => $msg->{slide_num}, step_num => $msg->{step_num});
			}
		}
	});
	$c->inactivity_timeout(3600);
	#my $keepalive= Mojo::IOLoop->recurring(60 => sub { $viewers{$id}->send([1, 0, 0, 0, WS_PING, '']); });
	#$c->stash(keepalive => $keepalive);
	$c->on(finish => sub {
		#Mojo::IOLoop->remove($keepalive);
		delete $viewers{$id};
		update_published_state(viewer_count => scalar keys %viewers);
	});
};

push @ARGV, qw( daemon -l http://*:2000 ) unless @ARGV;
app->start;
