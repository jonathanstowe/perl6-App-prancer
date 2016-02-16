=begin pod

=head1 App::Prancer::Handler

Lets you define your own custom route handlers using nothing but a
C<is handler> trait.

=head1 Synopsis

    use App::Prancer::Handler;

    multi GET( 'posts', Int:D $page ) is handler
        { "<html><head/><body>Page $page of posts</body></html>" }

=head1 Documentation

You can define HTTP/1.1 URLs as ordinary Perl 6 subroutines. Name the method
the same as the HTTP/1.1 method you want to capture, and give the URL as the
first argument of your subroutine. To keep clutter to a minimum, each of the
sample handler blocks will simply return an exact copy of their URL, excepting
a few cases where we want to point out differences.

    GET /posts HTTP/1.1 # can be captured as:
    multi GET( 'posts' ) is handler
      { return "/posts" }

If your URL has more than one path element in them, you can use the C</>
path separator, or list the two path elements as separate arguments.

    multi GET( 'posts/page' ) is handler { }
    multi GET( 'posts', 'page' ) is handler
      { return "/posts/page" }

are the same handler. If you want to use more of a REST-style URL, you can
use ordinary Perl parameters as part of your parameter list.

    GET /posts/DrForr HTTP/1.1
    multi GET( 'posts', Str:D $username ) is handler
      { return "/posts/$username" }

You can use regular expressions in your URLs as well, just use a constraint as
you normally would in Perl 6. Regular expression matches are tried first,
followed by any catchall terms you may have supplied.

    GET /team/jersey-devils HTTP/1.1
    multi GET( 'team', Str:D $team where { /\w+\-\w+/ } ) is handler
      { return "/team/$team (hyphenated)" }
    multi GET( 'team', Str:D $team ) is handler
      { return "/team/$team" }

Last, but not least, wildcards are also just Perl variables. If you want to
match anything, just declare a parameter with no types. Or if you want to
match anything under a given URL, declare an array which will be filled with
the rest of the path. Not a slurpy array though, that does something different.

    GET /path/to/my/deeply-buried-avatar.png HTTP/1.1
    multi GET( 'path', $to, @path-to-avatar ) is handler
      { return "/path/$to/@path-to-avatar" }

=head1 Query arguments

Of course, any method can take arguments afterward. You can generally access
those in two ways. Declare a C<$QUERY> parameter if you want to capture all
of the arguments from the URL. Note that this is a C<Hash::MultiValue> object
because there may be more than one instance of an argument in the URL. There
probably shouldn't be, but there's no accounting for taste, or malicious users
trying to inject data.

    GET /post/?slug=my_amazing_post&id=1 HTTP/1.1
    multi GET( 'post', $QUERY ) is handler
      { return "/post/?slug=$QUERY.<slug>\&id=$QUERY.<id>" }

Your existing HTML may already pass in an argument named C<QUERY>, so feel free
to use the destructuring-bind version of the call, if that's the case. Or just
check the global %QUERY hash. (This may change, once I figure out a better way
to pass out-of-band information to your function.)

    GET /post/?slug=my_amazing_post&id=1 HTTP/1.1
    multi GET( 'post', [ $slug, $id ] ) is handler
      { return "/post/?slug=$slug\&id=$id" }

=head1 Form parameters

It's common for forms to have parameters in their bodies, so we pass back
either C<$BODY> for that, or pass the variables back to the destructuring-bind
arguments.

    POST /post HTTP/1.1 [slug=value, id=value]
    multi POST( 'post', $QUERY ) is handler
      { return "/post/?slug=$QUERY.<slug>\&id=$QUERY.<id>" }
    multi POST( 'post', [ $slug, $id ] ) is handler
      { return "/post/?slug=$slug\&id=$id" }

=head1 Fallback

Ultimately if none of these methods work for your URL, you can always ask to
have the original L<Crust> C<$env> variable passed to you:

    POST /post HTTP/1.1 [slug=value, id=value]
    multi POST( 'post', $CRUST_ENV ) is handler
      { return "/post/?slug=$CRUST_ENV.post_parameters.<slug>" }

=head1 Calling order

Generally L<Prancer> tries to call the most specific method it can for a given
URL. Literal parameters (C<'foo'>) are tried first, followed by regular
expressions, then types, followed by untyped parameters. If all else fails,
the array fallbacks are checked. If those should fail, it looks in the C<static>
directory for files to serve, otherwise it throws a 404 error.

When it's been integrated it'll use Riak's WebMachine state diagram to actually
handle the return codes, that's an eventual improvement.

=end pod

class App::Prancer::Handler
	{
	has Bool $!trace = False;

	use Crust::Runner;

# {{{ routine-to-handler
	sub routine-to-handler( Routine $r )
		{
		my $name      = $r.name;
		my $signature = $r.signature;
		my @params    = $signature.params;
		my @args;

		for $signature.params -> $param
			{
			if $param.name
				{
				@args.push( [ $param.type => $param.name ] )
				}
			else
				{
				my $path-element;

				# XXX Not sure why this is necessary, except for
				# XXX $param.constraints being a junction
				#
				for $param.constraints -> $constraint
					{
					$path-element = $constraint;
					last;
					}
				my @path = $path-element.split( '/', :skip-empty );
				@args.append( @path );
				}
			}
		@args = ( Nil ) if !@args;

		return
			{
			name      => $r.name,
			arguments => @args,
			routine   => $r
			}
		}
# }}}

	my $trie = {};

	sub insert-routine( @args, $r )
		{
		$trie.{@args[0]} = $r;
		}

	multi sub trait_mod:<is>( Routine $r, :$handler! ) is export
		{
		$trie.<x> = 1;
		my $info = routine-to-handler( $r );
		return unless $info.<name> ~~
			      <DELETE GET HEAD OPTIONS PATCH POST PUT>.any;
		my @args = ( $info.<name>, $info.<arguments>.flat ).flat;
say @args;
		insert-routine( @args, $r );
#	insert-routine( $handler-trie, @args, $r );
		}

	method make-app()
		{
		my $trace-on = $!trace;
		return sub ( $env )
			{
say "Tracing" if $trace-on;
			return	200,
				[ 'Content-Type' => 'text/plain' ],
				[ "Fallback" ]
			}
		}

	method prance( $trace )
		{
		$!trace = $trace;
		my $runner = Crust::Runner.new;
		$runner.run( self.make-app );
		}

	method display-routes()
		{
		for my $trie.keys -> $key
			{
			}
		}

	sub prance( :$trace = False, :$verbose = False ) is export
		{
		my $app = App::Prancer::Handler.new;
#		$app.display-routes if $verbose;
say $trie if $verbose;
say $trie;
		$app.prance( $trace );
		}
	}
