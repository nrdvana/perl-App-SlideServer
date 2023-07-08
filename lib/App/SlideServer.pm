package App::SlideServer;
use v5.36;
use Mojo::Base 'Mojolicious';
use Mojo::WebSocket 'WS_PING';
use Mojo::File 'path';
use Mojo::DOM;
use Log::Any '$log';
use Text::Markdown::Hoedown;

#VERSION
#ABSTRACT: Mojo web server that serves slides and websocket

=head1 SYNOPSIS

   use App::SlideServer;
   my $app= App::SlideServer->new(\%opts);
   $app->start(qw( daemon -l http://*:2000 ));

=head1 DESCRIPTION

This class is a fairly simple Mojo web application that serves a small
directory of files, one of which is a Markdown or HTML document containing
your slides.

On startup, the application upgrades your slides to a proper HTML structure
(see L<HTML SPECIFICATION>) possibly by first running it through a Markdown
renderer if you provided the slides as markdown instead of HTML.  It then
inspects the HTML and breaks it apart into one or more slides (by default,
splitting on all H1, H2, H3, HR, or any C<< <div class="slide"> >> elements).

You may then start the Mojo application as a webserver, or whatever else you
wanted to do with the Mojo API.

The application comes with a collection of web assets that render your HTML
to look like "normal" slides that you would expect for a live presentation.
The default javascript downloads the slides one at a time, and only after
the "presenter" connection has advanced to the slide, so viewers can only
see as much as you have allowed them to see.  Users can scroll backward to
look at earlier slides, if you allow them to (controlled with javascript).

=head1 CONSTRUCTOR

This is a standard Mojolicious object with a Mojo::Base C<< ->new >> constructor.

=head1 ATTRIBUTES

=head2 serve_dir

This is a Mojo::File object of the diretory containing templates and public
files.  Public files live under C<< $serve_dir/public >>.
See L</slides_source_file> for the location of your slides.

The default is C<< $self->home >> (Mojolicious project root dir)

=cut

# Files supplied by the user to override the distribution
has serve_dir => sub { path(shift->home) };

=head2 slides_source_file

Specify the actual path to the file containing your slides.  The default is
to use the first existing file of:

   * $serve_dir/slides.html
   * $serve_dir/slides.md
   * $serve_dir/public/slides.html
   * $serve_dir/public/slides.md

Note that files in public/ can be downloaded as-is by the public at any time.
...but maybe that's what you want.

=cut

# Choose the first of 
sub slides_source_file($self, $value=undef) {
	$self->{slides_source_file}= $value if defined $value;
	$self->{slides_source_file} // do {
		my ($src)= grep -f $_,
			$self->serve_dir->child('slides.html'),
			$self->serve_dir->child('slides.md'),
			$self->serve_dir->child('public','slides.html'),
			$self->serve_dir->child('public','slides.md'),
	}
}

=head2 share_dir

This is a Mojo::File object of the directory containing the web assets that
come with App::SlideServer.  The default uses File::ShareDir and should
'just work' for you.

=cut

# Files that ship with the distribution
has share_dir => sub {
	if (-f path(__FILE__)->sibling('..','..','share','public','slides.js')) {
		return path(__FILE__)->sibling('..','..','share')->realpath;
	} else {
		require File::ShareDir;
		return path(File::ShareDir::dist_dir('App-SlideServer'));
	}
};

=head2 presenter_key

This is a secret string that only you (the presenter) should know.
It is your password to let the server know that your browser is the one that
should be controlling the presentation.

If you don't initialize this, it defaults to a random value which will be
printed on STDOUT where (presumably) only you can see it.

=cut

# A secret known only to whoever starts the server
# Clients must send this to gain presenter permission.
has presenter_key => sub {
	my $key= sprintf "%06d", rand 1000000;
	$log->info("Auto-generated presenter key: $key");
	return $key;
};

=head2 viewers

A hashref of C<< ID => $context >> where C<$context> is the Mojo context
object for the client's websocket connection, and ID is the request ID for
that websocket.  This is updated as clients connect or disconnect.

=cut

# Hashref of { ID => $context } for every connected websocket
has viewers => sub { +{} };

=head2 published_state

A hashref of various data which has been broadcast to all viewers.
This keeps track of things like the current slide, but you can extend it
however you like if you want to add features to the client javascript.
Use L</update_published_state> to make changes to it.

=cut

# Hashref of data to be pushed to all clients
has published_state => sub { +{} };

=head2 page_dom

This is a Mojo::DOM object holding the page that is served as "/" containing
the client javascript and css (but not any of the slides).
This is a cached output of L</build_slides> and may be rebuilt at any time.

=head2 slides_dom

This is an arrayref of the individual slides (Mojo::DOM objects) that the
application serves.  This is a cached output of L</build_slides> and may be
rebuilt at any time.

=cut

has ['index_page', 'slides'];

sub startup($self) {
	$self->build_slides;
	$self->presenter_key;
	$self->static->paths([ $self->share_dir->child('public'), $self->serve_dir->child('public') ]);
	$self->routes->get('/' => sub($c){ $c->render(text => $c->app->render_slides) });
	$self->routes->websocket('/slidelink.io' => sub($c){ $c->app->init_websocket($c) });
}

=head1 METHODS

=head2 build_slides

This calls L</load_slides_html> (which calls C<markdown_to_html> if your
source is markdown) then calls L</extract_slides_dom> to break the HTML into
Mojo::DOM objects (and restructure shorthand notations into proper HTML),
then calls L</merge_page_assets> to augment the top-level page with the web
assets like javascript and css needed for the client slide UI, then stores
this result in L</page_dom> and L</slides_dom> and returns C<$self>.
It throws exceptions if it fails, leaving previous results intact.

You can override any of those methods in a subclass to customize this process.

This method is called automatically at startup and any time the mtime of your
source file changes. (detected lazily when serving '/')  

=cut

sub build_slides($self) {
	my $html= $self->load_slides_html;
	my ($page, @slides)= $self->extract_slides_dom($html);
	$page= $self->merge_page_assets($page);
	$self->page_dom($page);
	$self->slides_dom(\@slides);
	return \@slides;
}

=head2 load_slides_html

Reads L</slides_source_file>, calls L</markdown_to_html> if it was markdown,
and returns the content as a string.

=cut

sub load_slides_html($self) {
	my $srcfile= $self->slides_source_file
		or croak "No source file; require slides.md or slides.html in serve_dir '".$self->serve_dir."'\n";
	my $content= $srcfile->slurp;
	$content= $self->markdown_to_html($content)
		if $srcfile =~ /[.]md$/;
	return $content;
}

=head2 markdown_to_html

  $html= $app->markdown_to_html($md);

This is a simple wrapper around Markdown::Hoedown with most of the syntax
options enabled.  You can substitute any markdown processor you like in a
subclass.

=cut

sub markdown_to_html($self, $md) {
	return markdown($md, extensions => (
		HOEDOWN_EXT_TABLES | HOEDOWN_EXT_FENCED_CODE | HOEDOWN_EXT_AUTOLINK | HOEDOWN_EXT_STRIKETHROUGH
		| HOEDOWN_EXT_UNDERLINE | HOEDOWN_EXT_QUOTE | HOEDOWN_EXT_SUPERSCRIPT | HOEDOWN_EXT_NO_INTRA_EMPHASIS
		| HOEDOWN_EXT_DISABLE_INDENTED_CODE
		)
	);
}

=head2 extract_slides_dom

This function takes loose shorthand HTML (or full HTML) and splits out the
slides content while also upgrading them to full HTML structure according to
L<HTML SPECIFICATION>.  It returns one Mojo::DOM object for the top-level
page, and one Mojo::DOM object for each detected slide, as a list.

=cut

sub _node_is_slide($self, $node, $tag) {
	return $tag eq 'DIV' && $node->{class} =~ /\bslide\b/;
}
sub _node_starts_slide($self, $node, $tag) {
	return $tag eq 'H1' || $tag eq 'H2' || $tag eq 'H3';
}
sub _node_splits_slide($self, $node, $tag) {
	return $tag eq 'HR';
}

sub extract_slides_dom($self, $html) {
	my $dom= Mojo::DOM->new($html);
	# Find each element that is an immediate child of body, and add it to
	# the current slide until the next <h1> <h2> <h3> <hr> or <div class="slide">
	# at which point, move to the next slide.
	my @slides, $cur_slide;
	for my $node (($dom->at('div.slides') || $dom->at('body') || $dom)->@*) {
		$node->remove;
		my $tag= uc($node->tag // '');
		# is it a whole pre-defined slide?
		if ($self->_node_is_slide($node, $tag)) {
			$cur_slide= undef;
			push @slides, $node;
		}
		elsif ($self->_node_splits_slide($node, $tag)) {
			$cur_slide= undef;
		}
		else {
			push @slides, ($cur_slide= Mojo::DOM->new('<div class="slide"></div>'))
				if !defined $cur_slide
					|| $self->_node_starts_slide($node, $tag);
			# Add "auto-step" to any <UL> tags
			$node->{class}= "auto-step" if ($tag eq 'UL' || $tag eq 'OL') && !$node->{class};
			$cur_slide->append_content($node);
		}
	}
	return ($dom, @slides);
}	

sub merge_page_assets($self, $srcdom) {
	my $page= Mojo::DOM->new($self->share_dir->child('page_template.html')->slurp);
	if (my $srchead= $srcdom->at('head')) {
		my $pagehead= $page->at('head');
		# Prevent conflicting tags (TODO, more...)
		if (my $title= $srchead->at('title')) {
			$pagehead->at('title')->remove;
		}
		$pagehead->append_content($_) for $srchead->@*;
	}
	if (my $srcbody= $srcdom->at('body')) {
		if ($srcbody->child_nodes->size) {
			$page->at('body')->replace($srcbody);
			if (!$page->at('body div.slides')) {
				$page->at('body')->append_content('<div class="slides"></div>');
			}
		} else {
			$page->at('body')->%*= $srcbody->%*;
		}
	}
	return $page;
}

=head2 update_published_state

  $app->update_published_state( $k => $v, ...)

Apply any number of key/value pairs to the L</published_state>, and then
push it out to all L</viewers>.

=cut

sub update_published_state($self, @new_attrs) {
	$self->published_state->%* = ( $self->published_state->%*, @new_attrs );
	$_->send({ json => { state => $self->published_state } })
		for values $self->viewers->%*;
}

=head2 init_websocket

Handle an incoming websocket connection.  This method determines whether the
new connection is a presenter or not, and then sets up the events and adds it
to L</viewers> and pushes out a copy of L</published_state> to the new client.

=cut

sub init_websocket($self, $c) {
	my $id= $c->req->request_id;
	$self->viewers->{$id}= $c;
	my $mode= $c->req->param('mode');
	my $key= $c->req->param('key');
	my %roles= ( follow => 1 );
	if ($mode eq 'presenter') {
		if (($key||'') eq $self->presenter_key) {
			$roles{lead}= 1;
			$roles{navigate}= 1;
			$self->update_published_state(viewer_count => scalar keys $self->viewers->%*);
		}
	}
	$c->stash('roles', join ',', keys %roles);
	$log->infof("%s (%s) connected as %s", $id, $c->tx->remote_address, $c->stash('roles'));
	$c->send({ json => { roles => [ keys %roles ] } });
	
	$c->on(json => sub($c, $msg, @) { $c->app->on_viewer_message($c, $msg) });
	$c->on(finish => sub($c, @) { $c->app->on_viewer_disconnect($c) });
	$c->inactivity_timeout(3600);
	#my $keepalive= Mojo::IOLoop->recurring(60 => sub { $viewers{$id}->send([1, 0, 0, 0, WS_PING, '']); });
	#$c->stash(keepalive => $keepalive);
}

=head2 on_viewer_message

Handle an incoming message from a websocket.

=head2 on_viewer_disconnect

Handle a disconnect event form a websocket.

=cut

sub on_viewer_message($self, $c, $msg) {
	my $id= $c->req->request_id;
	$log->debugf("client %s %s msg=%s", $id, $c->tx->original_remote_address, $msg) if $log->is_debug;
	if ($c->stash('roles') =~ /\blead\b/) {
		if (defined $msg->{extern}) {
		}
		if (defined $msg->{slide_num}) {
			$self->update_published_state(slide_num => $msg->{slide_num}, step_num => $msg->{step_num});
		}
	}
#	if ($c->stash('roles') =~ /\b
}

sub on_viewer_disconnect($self, $c) {
	my $id= $c->req->request_id;
	#Mojo::IOLoop->remove($keepalive);
	delete $self->viewers->{$id};
	$self->update_published_state(viewer_count => scalar keys $self->viewers->%*);
}

1;
