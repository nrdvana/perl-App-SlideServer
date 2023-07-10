<h1 style="font-family: monospace; padding-top:2em;">App::SlideServer</span></h1>

<br>

Follow Along at <a href="https://nrdvana.net/presentations/app-slideserver">https://nrdvana.net/presentations/app-slideserver</a><br>
GitHub: <a href="https://github.com/nrdvana/perl-App-SlideServer">nrdvana/perl-App-SlideServer</a><br>

<br>

<center>
Michael Conrad<br>
CPAN: NERDVANA
</center>

## Features

  * Write markdown, present as a slide show
  * Multiple connections, synchronized
  * Multiple control connections
  * Run locally or from Internet
  * Simple design
  * Slides can operate without server

<pre class="notes">
  All you need is markdown
  Cool presentation mode
  Multiple device control, like Keynote
  low complexity, high flexibility
  easy to publish slides without a server
</pre>

## Design

  * Tech Stack: Mojo, jQuery, HTML, CSS
  * Single Perl Module, easy to subclass
  * ES5 JavaScript, no tooling needed
  * Perl backend serves slides
  * JavaScript frontend renders slides

<pre class="notes">
  
</pre>

## Design, Backend

  * Commandline "bin/slide-server"
  * Mojo App: App::SlideServer
     * method load_slides_html
     * method markdown_to_html
     * method extract_slides_dom
     * controller "/"       => serve_page
     * controller "/slides" => serve_slides

<pre class="notes">
</pre>

## Design, Frontend

  * Page initiates websocket
  * Presenter navigation relays messages through websocket
  * Viewers receive presenter's events
  * Viewers load slide HTML
  * Viewers resize the HTML to fit the viewport

<pre class="notes">
</pre>

<h1 style="padding: 2em 0">Questions?</h1>
