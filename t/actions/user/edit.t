use strict;
use Test::More;

use Catalyst::Test 'MusicBrainz::Server';
use MusicBrainz::Server::Email;
use MusicBrainz::Server::Test qw( xml_ok );
use Test::WWW::Mechanize::Catalyst;

MusicBrainz::Server::Test->prepare_test_server;

my $c = MusicBrainz::Server::Test->create_test_context;
my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'MusicBrainz::Server');

$mech->get('/login');
$mech->submit_form( with_fields => { username => 'new_editor', password => 'password' } );

$mech->get_ok('/account/edit');
xml_ok($mech->content);
$mech->submit_form( with_fields => {
    'profile.website' => 'foo',
    'profile.biography' => 'hello world!',
} );
$mech->content_contains('Invalid URL format');
$mech->submit_form( with_fields => {
    'profile.website' => 'http://example.com/~new_editor/',
    'profile.biography' => 'hello world!',
    'profile.email' => 'new_email@example.com',
} );
$mech->content_contains('Your profile has been updated');
$mech->content_contains('We have sent you a verification email');

my $email_transport = MusicBrainz::Server::Email->get_test_transport;
my $email = $email_transport->deliveries->[-1]->{email};
is($email->get_header('To'), 'new_email@example.com');
is($email->get_header('Subject'), 'Please verify your email address');
like($email->get_body, qr{http://localhost/verify-email.*});

$email->get_body =~ qr{http://localhost(/verify-email.*)};
my $verify_email_path = $1;
$mech->get_ok($verify_email_path);
$mech->content_contains("Thank you, your email address has now been verified!");

$mech->get('/user/profile/new_editor');
$mech->content_contains('http://example.com/~new_editor/');
$mech->content_contains('hello world!');
$mech->content_contains('new_email@example.com');

done_testing;