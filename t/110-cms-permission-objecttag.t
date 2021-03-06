#!/usr/bin/perl

use strict;
use warnings;

BEGIN {
    $ENV{MT_CONFIG} = 'mysql-test.cfg';
}

use lib 't/lib', 'lib', 'extlib';
use MT::Test qw( :app :db );
use MT::Test::Permission;
use Test::More;

### Make test data

# Website
my $website = MT::Test::Permission->make_website();

# Blog
my $blog = MT::Test::Permission->make_blog(
    parent_id => $website->id,
);

# Author
my $aikawa = MT::Test::Permission->make_author(
    name => 'aikawa',
    nickname => 'Ichiro Aikawa',
);

my $admin = MT::Author->load(1);

# Role
require MT::Role;
my $blog_admin = MT::Role->load( { name => MT->translate( 'Blog Administrator' ) } );

require MT::Association;
MT::Association->link( $aikawa => $blog_admin => $blog );

# Run
my ( $app, $out );

subtest 'mode = list' => sub {
    my $ot = MT::Test::Permission->make_objecttag( blog_id => $blog->id );
    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $admin,
            __request_method => 'POST',
            __mode           => 'list',
            _type            => 'objecttag',
            blog_id          => $blog->id,
        }
    );
    $out = delete $app->{__test_output};
    ok( $out, "Request: list" );
    ok( $out =~ m!Unknown Action!i, "list by admin" );

    $ot = MT::Test::Permission->make_objecttag( blog_id => $blog->id );
    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $aikawa,
            __request_method => 'POST',
            __mode           => 'list',
            _type            => 'objecttag',
            blog_id          => $blog->id,
        }
    );
    $out = delete $app->{__test_output};
    ok( $out, "Request: list" );
    ok( $out =~ m!Unknown Action!i, "list by non permitted user" );
};

subtest 'mode = save' => sub {
    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $admin,
            __request_method => 'POST',
            __mode           => 'save',
            _type            => 'objecttag',
            blog_id          => $blog->id,
            object_id        => 1,
            object_ds        => 'entry',
            tag_id           => 1,
        }
    );
    $out = delete $app->{__test_output};
    ok( $out, "Request: save" );
    ok( $out =~ m!Invalid Request!i, "save by admin" );

    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $aikawa,
            __request_method => 'POST',
            __mode           => 'save',
            _type            => 'config',
            _type            => 'objecttag',
            blog_id          => $blog->id,
            object_id        => 1,
            object_ds        => 'entry',
            tag_id           => 1,
        }
    );
    $out = delete $app->{__test_output};
    ok( $out, "Request: save" );
    ok( $out =~ m!Invalid Request!i, "save by non permitted user" );
};

subtest 'mode = edit' => sub {
    my $ot = MT::Test::Permission->make_objecttag( blog_id => $blog->id );
    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $admin,
            __request_method => 'POST',
            __mode           => 'edit',
            _type            => 'objecttag',
            blog_id          => $blog->id,
            id               => $ot->id,
        }
    );
    $out = delete $app->{__test_output};
    ok( $out, "Request: edit" );
    ok( $out =~ m!Invalid Request!i, "edit by admin" );

    $ot = MT::Test::Permission->make_objecttag( blog_id => $blog->id );
    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $aikawa,
            __request_method => 'POST',
            __mode           => 'edit',
            _type            => 'objecttag',
            blog_id          => $blog->id,
            id               => $ot->id,
        }
    );
    $out = delete $app->{__test_output};
    ok( $out, "Request: edit" );
    ok( $out =~ m!Invalid Request!i, "edit by non permitted user" );
};

subtest 'mode = delete' => sub {
    my $ot = MT::Test::Permission->make_objecttag( blog_id => $blog->id );
    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $admin,
            __request_method => 'POST',
            __mode           => 'delete',
            _type            => 'objecttag',
            blog_id          => $blog->id,
            id               => $ot->id,
        }
    );
    $out = delete $app->{__test_output};
    ok( $out, "Request: delete" );
    ok( $out =~ m!Invalid Request!i, "delete by admin" );

    $ot = MT::Test::Permission->make_objecttag( blog_id => $blog->id );
    $app = _run_app(
        'MT::App::CMS',
        {   __test_user      => $aikawa,
            __request_method => 'POST',
            __mode           => 'delete',
            _type            => 'objecttag',
            blog_id          => $blog->id,
            id               => $ot->id,
        }
    );
    $out = delete $app->{__test_output};
    ok( $out, "Request: delete" );
    ok( $out =~ m!Invalid Request!i, "delete by non permitted user" );
};

done_testing();
