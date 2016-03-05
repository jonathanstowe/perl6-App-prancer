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

=head1 Ordering

=head1 Arguments

=head2 Query arguments

Of course, any method can take query arguments. Rather than cluttering up the
argument list, just use the C<$*QUERY> variable to check the query arguments.
This will be a C<Hash::MultiValue> object as keys can occur multiple times in
a given query.

    GET /post/?slug=my_amazing_post&id=1 HTTP/1.1
    multi GET( 'post' ) is handler
      { return "/post/?slug=$*QUERY.<slug>\&id=$*QUERY.<id>" }

=head2 Form parameters

Likewise, C<POST> methods have form content, so look for that in the C<$*BODY>
argument.

    POST /post HTTP/1.1 [slug=value, id=value]
    multi POST( 'post' ) is handler
      { return "/post/?slug=$BODY.<slug>\&id=$BODY.<id>" }

=head2 Cookies

If you need session management, you can use C<App::Prancer::Plugin::Session>
and add C<$*SESSION> to manipulate user sessions. Otherwise use C<$*COOKIES>
to view and update cookies.

=head1 Fallback

Ultimately if none of these methods work for your URL, you can always ask to
have the original L<Crust> C<$env> variable passed to you in C<%*ENV>:

    POST /post HTTP/1.1 [slug=value, id=value]
    multi POST( 'post' ) is handler
      { return "/post/?slug=$*ENV.post_parameters.<slug>" }

=head1 Calling order

=over

=item Static files

=item Dynamic routes with only literal terms

=item Dynamic routes with variables that aren't C<Int> or C<Str>

=item Dynamic routes with C<Int> variables

=item Dynamic routes with C<Str> variables

=item Otherwise a 404 File Not Found response is returned.

=back

Parameters are checked from left to right, so if two or more handlers can match
a given path, the one that matches the first term wins. Take a look at
C<find-route> in L<App::Prancer::Handler> for more information, or see the test
suite.

=end pod

use App::Prancer::Routes;

#`(
#use Crust::Handler::HTTP::Server::Tiny;

use URI;
use Crust::Runner;
use Crust::MIME;

#	my $uri = URI.new( "$env.<p6sgi.url-scheme>://$env.<REMOTE_HOST>$env.<PATH_INFO>?$env.<QUERY_STRING>" );
)

constant STATIC-DIRECTORY = 'static';
constant HTTP-REQUEST-METHODS =
	<DELETE GET HEAD OPTIONS PATCH POST PUT>;

our $PRANCER-INTERNAL-ROUTES = App::Prancer::Routes.new;

sub routine-to-handler( Routine $r )
	{
	my $signature = $r.signature;
	my @parameters;

	for $signature.params -> $param
		{
		my $rv;
		if $param.name { $rv = '#(' ~ $param.type.perl ~ ')' }
		else           { $rv = param-to-string( $param ) }

		@parameters.append( $rv );
		}

	return @parameters
	}

sub param-to-string( $param )
	{
	my $path-element;

	# XXX Not sure why this is necessary, except for
	# XXX $param.constraints being a junction
	#
	for $param.constraints -> $constraint
		{
		return $constraint;
		}
	}

my class Route-Info
	{
	has Routine $.r;
	}

multi sub trait_mod:<is>( Routine $r, :$handler! ) is export(:testing,:ALL)
	{
	my $name      = $r.name;
	my $signature = $r.signature;

	my @names = routine-to-handler( $r );
	my $path  = @names.join('');
	my @path  = grep { $_ ne '' }, map { ~$_ }, $path.split(/\//, :v);

	$PRANCER-INTERNAL-ROUTES.add(
		$name, 
		Route-Info.new(:r($r)), # XXX For expansion purposes
		@path
		);
	}

sub app( $env ) is export(:testing,:ALL)
	{
	my $response-code = 200;
	my $MIME-type     = 'text/HTML';
	my @content       = '';
	my $file          = STATIC-DIRECTORY ~ $env.<PATH_INFO>;

	if $file.IO.e and not $file.IO.d
		{
		$response-code = 200;
		$MIME-type     = Crust::MIME.mime-type( $file );
		@content       = ( $file.IO.slurp );
		}
	else
		{
		my $request-method = $env.<REQUEST_METHOD>;
		my @path = grep { $_ ne '' },
			   map { ~$_ },
			   $env.<PATH_INFO>.split(/\//, :v);
		my $info = $PRANCER-INTERNAL-ROUTES.find(
				$request-method, $env.<PATH_INFO> );
		@content = $info.r.(|@path);
		}

	return	$response-code,
		[ 'Content-Type' => $MIME-type ],
		[ @content ];
	}

sub prance() is export
	{
	my $runner = Crust::Runner.new;
	$runner.run( &app )
	}
