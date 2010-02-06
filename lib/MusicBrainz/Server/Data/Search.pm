package MusicBrainz::Server::Data::Search;

use Moose;
use Class::MOP;
use JSON;
use Sql;
use Readonly;
use Data::Page;
use URI::Escape qw( uri_escape_utf8 );
use MusicBrainz::Server::Entity::SearchResult;
use MusicBrainz::Server::Entity::ArtistType;
use MusicBrainz::Server::Entity::ReleaseGroup;
use MusicBrainz::Server::Entity::ReleaseGroupType;
use MusicBrainz::Server::Entity::Language;
use MusicBrainz::Server::Entity::Script;
use MusicBrainz::Server::Entity::Release;
use MusicBrainz::Server::Entity::LabelType;
use MusicBrainz::Server::Entity::Annotation;
use MusicBrainz::Server::Data::Artist;
use MusicBrainz::Server::Data::Label;
use MusicBrainz::Server::Data::Recording;
use MusicBrainz::Server::Data::Release;
use MusicBrainz::Server::Data::ReleaseGroup;
use MusicBrainz::Server::Data::Work;
use MusicBrainz::Server::Data::Work;
use MusicBrainz::Server::Constants qw( $DARTIST_ID $DLABEL_ID );
use MusicBrainz::Server::Data::Utils qw( type_to_model );

extends 'MusicBrainz::Server::Data::Entity';

Readonly my %TYPE_TO_DATA_CLASS => (
    artist        => 'MusicBrainz::Server::Data::Artist',
    label         => 'MusicBrainz::Server::Data::Label',
    recording     => 'MusicBrainz::Server::Data::Recording',
    release       => 'MusicBrainz::Server::Data::Release',
    release_group => 'MusicBrainz::Server::Data::ReleaseGroup',
    work          => 'MusicBrainz::Server::Data::Work',
    tag           => 'MusicBrainz::Server::Data::Tag',
);

sub search
{
    my ($self, $type, $query_str, $limit, $offset) = @_;
    return ([], 0) unless $query_str && $type;

    $offset ||= 0;

    my $query;
    my $use_hard_search_limit = 1;
    my $hard_search_limit;
    my $deleted_entity = undef;

    if ($type eq "artist" || $type eq "label") {

        $deleted_entity = ($type eq "artist") ? $DARTIST_ID : $DLABEL_ID;

        my $extra_columns = '';
        $extra_columns .= 'entity.labelcode,' if $type eq 'label';

        $query = "
            SELECT
                entity.id,
                entity.gid,
                entity.comment,
                aname.name AS name,
                asortname.name AS sortname,
                entity.type,
                entity.begindate_year, entity.begindate_month, entity.begindate_day,
                entity.enddate_year, entity.enddate_month, entity.enddate_day,
                $extra_columns
                MAX(rank) AS rank
            FROM
                (
                    SELECT id, ts_rank_cd(to_tsvector('mb_simple', name), query, 16) AS rank
                    FROM ${type}_name, plainto_tsquery('mb_simple', ?) AS query
                    WHERE to_tsvector('mb_simple', name) @@ query
                    ORDER BY rank DESC
                    LIMIT ?
                ) AS r
                LEFT JOIN ${type}_alias AS alias ON alias.name = r.id
                JOIN ${type} AS entity ON (r.id = entity.name OR r.id = entity.sortname OR alias.${type} = entity.id)
                JOIN ${type}_name AS aname ON entity.name = aname.id
                JOIN ${type}_name AS asortname ON entity.sortname = asortname.id
                WHERE entity.id != ?
            GROUP BY
                $extra_columns entity.id, entity.gid, entity.comment, aname.name, asortname.name, entity.type,
                entity.begindate_year, entity.begindate_month, entity.begindate_day,
                entity.enddate_year, entity.enddate_month, entity.enddate_day
            ORDER BY
                rank DESC, sortname, name
            OFFSET
                ?
        ";

        $hard_search_limit = $offset * 2;
    }
    elsif ($type eq "recording" || $type eq "release" || $type eq "release_group" || $type eq "work") {
        my $type2 = $type;
        $type2 = "track" if $type eq "recording";
        $type2 = "release" if $type eq "release_group";

        my $extra_columns = "";
        $extra_columns .= 'entity.type AS type_id,'
            if ($type eq 'release_group');

        $extra_columns = "entity.length,"
            if ($type eq "recording");

        $extra_columns .= 'entity.language, entity.script,'
            if ($type eq 'release');

        $query = "
            SELECT
                entity.id,
                entity.gid,
                entity.comment,
                entity.artist_credit AS artist_credit_id,
                $extra_columns
                r.name,
                r.rank
            FROM
                (
                    SELECT id, name, ts_rank_cd(to_tsvector('mb_simple', name), query, 16) AS rank
                    FROM ${type2}_name, plainto_tsquery('mb_simple', ?) AS query
                    WHERE to_tsvector('mb_simple', name) @@ query
                    ORDER BY rank DESC
                    LIMIT ?
                ) AS r
                JOIN ${type} entity ON r.id = entity.name
            ORDER BY
                r.rank DESC, r.name, artist_credit
            OFFSET
                ?
        ";
        $hard_search_limit = int($offset * 1.2);
    }
    elsif ($type eq "tag") {
        $query = "
            SELECT id, name, ts_rank_cd(to_tsvector('mb_simple', name), query, 16) AS rank
            FROM tag, plainto_tsquery('mb_simple', ?) AS query
            WHERE to_tsvector('mb_simple', name) @@ query
            ORDER BY rank DESC, tag.name
            OFFSET ?
        ";
        $use_hard_search_limit = 0;
    }

    if ($use_hard_search_limit) {
        $hard_search_limit += $limit * 3;
    }

    my $fuzzy_search_limit = 10000;
    my $search_timeout = 60 * 1000;

    my $sql = Sql->new($self->c->dbh);
    $sql->auto_commit;
    $sql->do('SET SESSION gin_fuzzy_search_limit TO ?', $fuzzy_search_limit);
    $sql->auto_commit;
    $sql->do('SET SESSION statement_timeout TO ?', $search_timeout);

    my @query_args = ();
    push @query_args, $hard_search_limit if $use_hard_search_limit;
    push @query_args, $deleted_entity if $deleted_entity;
    push @query_args, $offset;

    $sql->select($query, $query_str, @query_args);

    my @result;
    my $pos = $offset + 1;
    while ($limit--) {
        my $row = $sql->next_row_hash_ref or last;
        my $res = MusicBrainz::Server::Entity::SearchResult->new(
            position => $pos++,
            score => int(100 * $row->{rank}),
            entity => $TYPE_TO_DATA_CLASS{$type}->_new_from_row($row)
        );
        push @result, $res;
    }
    my $hits = $sql->row_count + $offset;
    $sql->finish;

    return (\@result, $hits);

}

# ---------------- External (Indexed) Search ----------------------

# The XML schema uses a slightly different terminology for things
# and the schema defines how data is passed between the main
# server and the search server. In order to shove the dat back into
# the object model, we need to do some ugly ass tweaking....

# The mapping of XML/JSON centric terms to object model terms.
my %mapping = (
    'disambiguation' => 'comment',
    'sort-name'      => 'sort_name',
    'title'          => 'name',
    'artist-credit'  => 'artist_credit',
    'status'         => '',
    'country'        => '',
    'label-code'     => 'label_code',
);

# Fix up the key names so that the data returned from the JSON service
# matches up with the data returned from the DB for easy object creation
sub schema_fixup
{
    my ($self, $data, $c, $type) = @_;

    return unless (ref($data) eq 'HASH');

    if (exists $data->{id} && $type eq 'freedb')
    {
        $data->{discid} = $data->{id};
        delete $data->{name};
    }

    # Special case to handle the ids
    $data->{gid} = $data->{id};
    $data->{id} = 1;

    foreach my $k (keys %mapping)
    {
        if (exists $data->{$k})
        {
            $data->{$mapping{$k}} = $data->{$k} if ($mapping{$k});
            delete $data->{$k};
        }
    }

    if ($type eq 'artist' && exists $data->{type})
    {
        $data->{type} = MusicBrainz::Server::Entity::ArtistType->new( name => $data->{type} );
    }
    if (($type eq 'artist' || $type eq 'label') && exists $data->{'life-span'})
    {
        $data->{begin_date} = MusicBrainz::Server::Entity::PartialDate->new($data->{'life-span'}->{begin}) 
            if (exists $data->{'life-span'}->{begin});
        $data->{end_date} = MusicBrainz::Server::Entity::PartialDate->new($data->{'life-span'}->{end}) 
            if (exists $data->{'life-span'}->{end});
    }
    if ($type eq 'label' && exists $data->{type})
    {
        $data->{type} = MusicBrainz::Server::Entity::LabelType->new( name => $data->{type} );
    }
    if ($type eq 'release-group' && exists $data->{type})
    {
        $data->{type} = MusicBrainz::Server::Entity::ReleaseGroupType->new( name => $data->{type} );
    }
    if ($type eq 'cdstub' && exists $data->{gid})
    {
        $data->{discid} = $data->{gid};
        delete $data->{gid};
        $data->{title} = $data->{name};
        delete $data->{name};
    }
    if ($type eq 'annotation' && exists $data->{entity})
    {
        my $entity_model = $c->model( type_to_model($data->{type}) )->_entity_class;
        $data->{parent} = $entity_model->new( { name => $data->{name}, gid => $data->{entity} });
        delete $data->{entity};
        delete $data->{type};
    }
    if ($type eq 'freedb' && exists $data->{name})
    {
        $data->{title} = $data->{name};
        delete $data->{name};
    }
    if (($type eq 'cdstub' || $type eq 'freedb') && (exists $data->{"track-list"} && exists $data->{"track-list"}->{count}))
    {
        $data->{track_count} = $data->{"track-list"}->{count};
        delete $data->{"track-list"}->{count};
    }
    if ($type eq 'release')
    {
        if (exists $data->{date})
        {
            $data->{date} = MusicBrainz::Server::Entity::PartialDate->new( name => $data->{date} );
        }
        if (exists $data->{"text-representation"} && 
            exists $data->{"text-representation"}->{language})
        {
            $data->{language} = MusicBrainz::Server::Entity::Language->new( { 
                iso_code_3t => $data->{"text-representation"}->{language} 
            } );
        }
        if (exists $data->{"text-representation"} && 
            exists $data->{"text-representation"}->{script})
        {
            $data->{script} = MusicBrainz::Server::Entity::Script->new( 
                    { iso_code => $data->{"text-representation"}->{script} }
            );
        }
        if (exists $data->{"medium-list"} && 
            exists $data->{"medium-list"}->{medium}->[0] && 
            exists $data->{"medium-list"}->{medium}->[0]->{"track-list"})
        {
            my $tracklist = MusicBrainz::Server::Entity::Tracklist->new( 
                track_count => $data->{"medium-list"}->{medium}->[0]->{"track-list"}->{count} 
            );
            $data->{mediums} = [ MusicBrainz::Server::Entity::Medium->new( 
                "tracklist" => $tracklist
            ) ];
            delete $data->{"medium-list"};
        }
    }
    if ($type eq 'recording' &&
        exists $data->{"release-list"} && 
        exists $data->{"release-list"}->{release}->[0] &&
        exists $data->{"release-list"}->{release}->[0]->{"medium-list"} &&
        exists $data->{"release-list"}->{release}->[0]->{"medium-list"}->{medium})
    {
        my @releases;

        foreach my $release (@{$data->{"release-list"}->{release}})
        {
            my $tracklist = MusicBrainz::Server::Entity::Tracklist->new(  
                track_count => $release->{"medium-list"}->{medium}->[0]->{"track-list"}->{count},
                tracks => [ MusicBrainz::Server::Entity::Track->new(
                    position => $release->{"medium-list"}->{medium}->[0]->{"track-list"}->{offset} 
                ) ]
            );
            my $release_group = MusicBrainz::Server::Entity::ReleaseGroup->new( 
                type => MusicBrainz::Server::Entity::ReleaseGroupType->new( 
                    name => $release->{"release-group"}->{type} || ''
                ) 
            );
            push @releases, MusicBrainz::Server::Entity::Release->new( 
                gid     => $release->{id},
                name    => $release->{title},
                mediums => [ 
                    MusicBrainz::Server::Entity::Medium->new( 
                         tracklist => $tracklist,
                         position  => $release->{"medium-list"}->{medium}->[0]->{"position"}
                    )
                ],
                release_group => $release_group
            );
        }
        $data->{_extra} = \@releases;
    }

    foreach my $k (keys %{$data})
    {
        if (ref($data->{$k}) eq 'HASH')
        {
            $self->schema_fixup($data->{$k}, $c, $type);
        }
        if (ref($data->{$k}) eq 'ARRAY')
        {
            foreach my $item (@{$data->{$k}})
            {
                $self->schema_fixup($item, $c, $type);
            }
        }
    }

    if (exists $data->{'artist_credit'})
    {
        my @credits;
        foreach my $namecredit (@{$data->{"artist_credit"}->{"name-credit"}})
        {
            push @credits, MusicBrainz::Server::Entity::ArtistCreditName->new( {
                    artist => MusicBrainz::Server::Entity::Artist->new($namecredit->{artist}),
                    join_phrase => $namecredit->{joinphrase} || '' } );
        }
        $data->{'artist_credit'} = MusicBrainz::Server::Entity::ArtistCredit->new( { names => \@credits } );
    }
}

# Escape special characters in a Lucene search query
sub escape_query
{
    my $str = shift;
    $str =~  s/([+\-&|!(){}\[\]\^"~*?:\\])/\\$1/g;
    return $str;
}

sub external_search
{
    my ($self, $c, $type, $query, $limit, $page, $adv, $ua) = @_;

    my $entity_model = $c->model( type_to_model($type) )->_entity_class;
    Class::MOP::load_class($entity_model);
    my $offset = ($page - 1) * $limit;

    if ($query eq '!!!' and $type eq 'artist')
    {
        $query = 'chkchkchk';
    }

    unless ($adv)
    {
        $query = escape_query($query);

        if ($type eq 'artist')
        {
            $query = "artist:($query)(sortname:($query) alias:($query) !artist:($query))";
        }
    }

    $query = uri_escape_utf8($query);
    $type =~ s/release_group/release-group/;
    my $search_url = sprintf("http://%s/ws/2/%s/?query=%s&offset=%s&max=%s&fmt=json",
                                 DBDefs::LUCENE_SERVER,
                                 $type,
                                 $query,
                                 $offset,
                                 $limit,);
    $c->log->debug($search_url);

    $ua = LWP::UserAgent->new if (!defined $ua);
    $ua->timeout (5);
    $ua->env_proxy;

    # Dispatch the search request.
    my $response = $ua->get($search_url);
    unless ($response->is_success)
    {
        return { code => $response->code, error => $response->content };
    }
    else
    {
        my $data = JSON->new->utf8->decode($response->content);

        my @results;
        my $xmltype = $type;
        $xmltype =~ s/freedb/freedb-disc/;
        my $pos = 0;
        foreach my $t (@{$data->{"$xmltype-list"}->{$xmltype}})
        {
            $self->schema_fixup($t, $c, $type);
            push @results, MusicBrainz::Server::Entity::SearchResult->new(
                    position => $pos++,
                    score  => $t->{score},
                    entity => $entity_model->new($t),
                    extra  => $t->{_extra} || []   # Not all data fits into the object model, this is for those cases
                );
        }
        my ($total_hits) = $data->{"$xmltype-list"}->{count};

        # If the user searches for annotations, they will get the results in wikiformat - we need to
        # convert this to HTML.
        if ($type eq 'annotation')
        {
            foreach my $result (@results)
            {
                use Text::WikiFormat;
                use DBDefs;

                $result->{entity}->text(Text::WikiFormat::format($result->{entity}->{text}, {}, 
                                        { 
                                          prefix => "http://".DBDefs::WIKITRANS_SERVER, 
                                          extended => 1, 
                                          absolute_links => 1, 
                                          implicit_links => 0 
                                        }));
                $result->{type} = ref($result->{entity}->{parent}); 
                $result->{type} =~ s/MusicBrainz::Server::Entity:://;
                $result->{type} = lc($result->{type});
            } 
        }

        if ($total_hits == 1 && ($type eq 'artist' || $type eq 'release' || 
            $type eq 'label' || $type eq 'release-group' || $type eq 'cdstub'))
        {
            my $redirect;

            $type =~ s/release-group/ReleaseGroup/;
            if ($type eq 'cdstub')
            {
                $redirect = $results[0]->{entity}->{discid};
            }
            else
            {
                $redirect = $results[0]->{entity}->{gid};
            }
            my $type_controller = $c->controller(type_to_model($type));
            my $action = $type_controller->action_for('show');

            $c->res->redirect($c->uri_for($action, [ $redirect ]));
            $c->detach;
        }
        
        my $pager = Data::Page->new;
        $pager->current_page($page);
        $pager->entries_per_page($limit);
        $pager->total_entries($total_hits);

        return { pager => $pager, offset => $offset, results => \@results };
    }
}
__PACKAGE__->meta->make_immutable;
no Moose;
1;

=head1 NAME

MusicBrainz::Server::Data::Search

=head1 COPYRIGHT

Copyright (C) 2009 Lukas Lalinsky

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=cut
