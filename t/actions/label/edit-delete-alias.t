use strict;
use Test::More;

use Catalyst::Test 'MusicBrainz::Server';
use MusicBrainz::Server::Test qw( xml_ok );
use Test::WWW::Mechanize::Catalyst;

my $c = MusicBrainz::Server::Test->create_test_context;
my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'MusicBrainz::Server');

$mech->get_ok('/login');
$mech->submit_form( with_fields => { username => 'new_editor', password => 'password' } );

$mech->get_ok('/label/46f0f4cd-8aab-4b33-b698-f459faf64190/alias/1/delete');
my $response = $mech->submit_form(
    with_fields => {
        'confirm.edit_note' => ''
    });

my $edit = MusicBrainz::Server::Test->get_latest_edit($c);
isa_ok($edit, 'MusicBrainz::Server::Edit::Label::DeleteAlias');
is_deeply($edit->data, {
    entity_id => 2,
    alias_id  => 1,
    name      => 'Test Label Alias',
});

$mech->get_ok('/edit/' . $edit->id, 'Fetch edit page');
xml_ok($mech->content, '..valid xml');
$mech->content_contains('Warp Records', '..has label name');
$mech->content_contains('Test Label Alias', '..has alias name');

done_testing;
