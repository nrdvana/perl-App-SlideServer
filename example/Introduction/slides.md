<style>
div.slide { min-width: 900px; }
</style>


<h1 style="font-family: monospace; padding-top:2em;">App::SlideServer</span></h1>

<br>

<div style="text-align:left; margin: 2em;">
  Follow Along at:<br>
  <a href="https://nrdvana.net/presentations/app-slideserver">nrdvana.net/presentations/app-slideserver</a><br>
  <br>
  Source:<br>
  <a href="https://github.com/nrdvana/perl-App-SlideServer">github.com/nrdvana/perl-App-SlideServer</a><br>
</div>

<center>
Michael Conrad<br>
mike@nrdvana.net<br>
CPAN: NERDVANA
</center>

## Features

  * Write markdown, present as a slide show
  * Multiple connections, synchronized
  * Multiple control connections
  * Run locally or from Internet
  * Live updates as you edit
  * Simple design
  * Slides can operate without server

<pre class=notes>
  If all you know is markdown, that's enough

  Cool presentation mode
  Multiple device control, like Keynote

  low complexity, high flexibility
  easy to publish slides without a server
</pre>

## Design

  * Tech Stack - Mojo, jQuery, HTML, CSS
  * Single Perl Module, easy to subclass
  * ES5 JavaScript, no tooling needed
  * Perl backend serves slides
  * JavaScript frontend renders slides

## Design, Backend

  * Commandline "bin/slide-server"
  * Mojolicious App::SlideServer
    * Load slides.md or slides.html
    * Fix sloppy html shorthands
    * Serve page and slides to frontend
    * Relay websocket events

## Design, Frontend

  * Page initiates websocket
  * Presenter navigation relays messages through websocket
  * Viewers receive events from presenter
  * Viewers load slide HTML
  * Viewers resize the HTML to fit the viewport

## HTML Structure

```
<body>
  <div class="slides">
    <div class="slide">
      <ul class="auto-step">
        <li>...
        <li>...
      </ul>
      <pre class="notes"> ... </pre>
    </div>
  </div>
</body>
```

## Markdown Structure

<div style="padding: 0 20%; font-size: 150%">
  <pre><code>
    ## Heading 2
    
      * Item 1
      * Item 2
      * Item 3
    
    &lt;pre class=notes>
       ...
    &lt;/pre>
    
  </code></pre>
</div>

## A complete Example

<iframe style="width: 700px; height: 600px;"
  src="/slides.md">
</iframe>

## Deploying to a Server

```
$ docker build -t slideserver -f share/Dockerfile .

$ docker create --name myslides -v $PWD:$PWD -w $PWD -p 80 .

$ docker start myslides && docker logs --follow myslides
```

<pre class=notes>
  makes docker image 'slideserver'
  uses current App::SlideServer on cpan
  makes docker container 'myslides'
  uses current dir slides.md or .html
</pre>

## Deploying under Traefik



## Future Work

  * More options for static page rendering
  * Color scheme controls in UI
  * GNU Screen integration
  * More robust auto-update
  * Better width/height automatic layout

<pre class=notes>
  static pages - inline images and js for local
  presenter should choose color scheme, users override
  live terminal to screen session
</notes>

