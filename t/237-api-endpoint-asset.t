#!/usr/bin/perl

use strict;
use warnings;

BEGIN {
    $ENV{MT_CONFIG} = 'mysql-test.cfg';
}

BEGIN {
    use Test::More;
    eval { require Test::MockModule }
        or plan skip_all => 'Test::MockModule is not installed';
}

use lib qw(lib extlib t/lib);

eval(
    $ENV{SKIP_REINITIALIZE_DATABASE}
    ? "use MT::Test qw(:app);"
    : "use MT::Test qw(:app :db :data);"
);

use MT::Util;
use MT::App::DataAPI;
my $app    = MT::App::DataAPI->new;
my $author = MT->model('author')->load(1);
$author->email('melody@example.com');
$author->save;

my $mock_author = Test::MockModule->new('MT::Author');
$mock_author->mock( 'is_superuser', sub {0} );
my $mock_app_api = Test::MockModule->new('MT::App::DataAPI');
$mock_app_api->mock( 'authenticate', $author );

my $temp_data = undef;
my @suite     = (
    {   path   => '/v1/sites/1/assets/upload',
        method => 'POST',
        setup  => sub {
            my ($data) = @_;
            $data->{count} = $app->model('asset')->count;
        },
        upload => [
            'file',
            File::Spec->catfile( $ENV{MT_HOME}, "t", 'images', 'test.jpg' ),
        ],
        result => sub {
            $app->model('asset')->load( { class => '*' },
                { sort => [ { column => 'id', desc => 'DESC' }, ] } );
        },
    },
    {   path   => '/v1/sites/1/assets/upload',
        method => 'POST',
        code   => '409',
        upload => [
            'file',
            File::Spec->catfile( $ENV{MT_HOME}, "t", 'images', 'test.jpg' ),
        ],
        complete => sub {
            my ( $data, $body ) = @_;
            my $result = MT::Util::from_json($body);
            $temp_data = $result->{error}{data};
            }
    },
    {   path   => '/v1/sites/1/assets/upload',
        method => 'POST',
        params => sub {
            +{  overwrite => 1,
                %$temp_data,
            };
        },
        upload => [
            'file',
            File::Spec->catfile( $ENV{MT_HOME}, "t", 'images', 'test.jpg' ),
        ],
    },
    {   path      => '/v2/sites/0/assets',
        method    => 'GET',
        callbacks => [
            {   name  => 'data_api_pre_load_filtered_list.asset',
                count => 2,
            },
        ],
        complete => sub {
            my ( $data, $body ) = @_;
            my $result = MT::Util::from_json($body);
            is( $result->{totalResults},
                4, 'The number of asset (blog_id=0) is 4.' );
        },
    },
    {   path      => '/v2/sites/1/assets',
        method    => 'GET',
        callbacks => [
            {   name  => 'data_api_pre_load_filtered_list.asset',
                count => 2,
            },
        ],
        complete => sub {
            my ( $data, $body ) = @_;
            my $result = MT::Util::from_json($body);
            is( $result->{totalResults},
                3, 'The number of asset (blog_id=1) is 3.' );
        },
    },
    {   path      => '/v2/sites/2/assets',
        method    => 'GET',
        callbacks => [
            {   name  => 'data_api_pre_load_filtered_list.asset',
                count => 2,
            },
        ],
        complete => sub {
            my ( $data, $body ) = @_;
            my $result = MT::Util::from_json($body);
            is( $result->{totalResults},
                3, 'The number of asset (blog_id=2) is 3.' );
        },
    },
    {   path   => '/v2/sites/3/assets',
        method => 'GET',
        code   => 404,
    },
    {   path      => '/v2/sites/1/assets',
        method    => 'GET',
        params    => { search => 'template', },
        callbacks => [
            {   name  => 'data_api_pre_load_filtered_list.asset',
                count => 2,
            },
        ],
        complete => sub {
            my ( $data, $body ) = @_;
            my $result = MT::Util::from_json($body);
            is( $result->{totalResults},
                1,
                'The number of asset whose label contains "template" is 1.' );
            like( lc $result->{items}[0]{label},
                qr/template/, 'The label of asset has "template".' );
        },
    },
    {   path      => '/v2/sites/1/assets',
        method    => 'GET',
        params    => { class => 'image', },
        callbacks => [
            {   name  => 'data_api_pre_load_filtered_list.asset',
                count => 2,
            },
        ],
        complete => sub {
            my ( $data, $body ) = @_;
            my $result = MT::Util::from_json($body);
            is( $result->{totalResults},
                2, 'The number of image asset is 2.' );
        },
    },
);

my %callbacks = ();
my $mock_mt   = Test::MockModule->new('MT');
$mock_mt->mock(
    'run_callbacks',
    sub {
        my ( $app, $meth, @param ) = @_;
        $callbacks{$meth} ||= [];
        push @{ $callbacks{$meth} }, \@param;
        $mock_mt->original('run_callbacks')->(@_);
    }
);

my $format = MT::DataAPI::Format->find_format('json');

for my $data (@suite) {
    $data->{setup}->($data) if $data->{setup};

    my $path = $data->{path};
    $path
        =~ s/:(?:(\w+)_id)|:(\w+)/ref $data->{$1} ? $data->{$1}->id : $data->{$2}/ge;

    my $params
        = ref $data->{params} eq 'CODE'
        ? $data->{params}->($data)
        : $data->{params};

    my $note = $path;
    if ( lc $data->{method} eq 'get' && $data->{params} ) {
        $note .= '?'
            . join( '&',
            map { $_ . '=' . $data->{params}{$_} }
                keys %{ $data->{params} } );
    }
    $note .= ' ' . $data->{method};
    $note .= ' ' . $data->{note} if $data->{note};
    note($note);

    %callbacks = ();
    _run_app(
        'MT::App::DataAPI',
        {   __path_info      => $path,
            __request_method => $data->{method},
            ( $data->{upload} ? ( __test_upload => $data->{upload} ) : () ),
            (   $params
                ? map {
                    $_ => ref $params->{$_}
                        ? MT::Util::to_json( $params->{$_} )
                        : $params->{$_};
                    }
                    keys %{$params}
                : ()
            ),
        }
    );
    my $out = delete $app->{__test_output};
    my ( $headers, $body ) = split /^\s*$/m, $out, 2;
    my %headers = map {
        my ( $k, $v ) = split /\s*:\s*/, $_, 2;
        $v =~ s/(\r\n|\r|\n)\z//;
        lc $k => $v
        }
        split /\n/, $headers;
    my $expected_status = $data->{code} || 200;
    is( $headers{status}, $expected_status, 'Status ' . $expected_status );
    if ( $data->{next_phase_url} ) {
        like(
            $headers{'x-mt-next-phase-url'},
            $data->{next_phase_url},
            'X-MT-Next-Phase-URL'
        );
    }

    foreach my $cb ( @{ $data->{callbacks} } ) {
        my $params_list = $callbacks{ $cb->{name} } || [];
        if ( my $params = $cb->{params} ) {
            for ( my $i = 0; $i < scalar(@$params); $i++ ) {
                is_deeply( $params_list->[$i], $cb->{params}[$i] );
            }
        }

        if ( my $c = $cb->{count} ) {
            is( @$params_list, $c,
                $cb->{name} . ' was called ' . $c . ' time(s)' );
        }
    }

    if ( my $expected_result = $data->{result} ) {
        $expected_result = $expected_result->( $data, $body )
            if ref $expected_result eq 'CODE';
        if ( UNIVERSAL::isa( $expected_result, 'MT::Object' ) ) {
            MT->instance->user($author);
            $expected_result = $format->{unserialize}->(
                $format->{serialize}->(
                    MT::DataAPI::Resource->from_object($expected_result)
                )
            );
        }

        my $result = $format->{unserialize}->($body);
        is_deeply( $result, $expected_result, 'result' );
    }

    if ( my $complete = $data->{complete} ) {
        $complete->( $data, $body );
    }
}

done_testing();
