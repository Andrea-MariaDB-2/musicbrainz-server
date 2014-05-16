package MusicBrainz::Server::Edit::Relationship::Reorder;
use strict;
use Moose;
use Moose::Util::TypeConstraints qw( as subtype find_type_constraint );
use MooseX::Types::Moose qw( ArrayRef Int Str Bool );
use MooseX::Types::Structured qw( Dict );
use MusicBrainz::Server::Constants qw(
    $EDIT_RELATIONSHIPS_REORDER
    $EXPIRE_ACCEPT
    :quality
);
use MusicBrainz::Server::Data::Utils qw( partial_date_to_hash type_to_model );
use MusicBrainz::Server::Edit::Exceptions;
use MusicBrainz::Server::Edit::Types qw( PartialDateHash );
use MusicBrainz::Server::Translation qw ( N_l );
use Try::Tiny;
use aliased 'MusicBrainz::Server::Entity::Link';
use aliased 'MusicBrainz::Server::Entity::Relationship';

extends 'MusicBrainz::Server::Edit';

sub edit_name { N_l('Reorder relationships') }
sub edit_kind { 'other' }
sub edit_type { $EDIT_RELATIONSHIPS_REORDER }

with 'MusicBrainz::Server::Edit::Role::Preview';
with 'MusicBrainz::Server::Edit::Relationship';
with 'MusicBrainz::Server::Edit::Relationship::RelatedEntities';

subtype 'LinkTypeHash'
    => as Dict[
        id => Int,
        name => Str,
        link_phrase => Str,
        reverse_link_phrase => Str,
        long_link_phrase => Str,
        entity0_type => Str,
        entity1_type => Str,
    ];

subtype 'ReorderedRelationshipHash'
    => as Dict[
        id => Int,
        attributes => ArrayRef[Int],
        begin_date => PartialDateHash,
        end_date => PartialDateHash,
        ended => Bool,
        entity0 => Dict[
            id => Int,
            name => Str,
        ],
        entity1 => Dict[
            id => Int,
            name => Str,
        ],
        attribute_text_values => Dict,
    ];

has '+data' => (
    isa => Dict[
        link_type => find_type_constraint('LinkTypeHash'),
        relationship_order => ArrayRef[
            Dict[
                relationship => find_type_constraint('ReorderedRelationshipHash'),
                old_order => Int,
                new_order => Int,
            ]
        ],
    ]
);

sub foreign_keys {
    my ($self) = @_;

    my $model0 = type_to_model($self->data->{link_type}{entity0_type});
    my $model1 = type_to_model($self->data->{link_type}{entity1_type});

    my %load;

    $load{LinkType} = [$self->data->{link_type}{id}];
    $load{LinkAttributeType} = [];
    $load{$model0} = {};
    $load{$model1} = {};

    for (map { $_->{relationship} } @{ $self->data->{relationship_order} }) {
        push @{ $load{LinkAttributeType} },
             @{ $_->{attributes} }, keys %{ $_->{attribute_text_values} };

        $load{$model0}->{ $_->{entity0}{id} } = [];
        $load{$model1}->{ $_->{entity1}{id} } = [];
    }

    return \%load;
}

sub _build_relationship {
    my ($self, $loaded, $data) = @_;

    my $lt = $self->data->{link_type};
    my $model0 = type_to_model($lt->{entity0_type});
    my $model1 = type_to_model($lt->{entity1_type});

    return Relationship->new(
        link => Link->new(
            type       => $loaded->{LinkType}{$lt->{id}} || LinkType->new($lt),
            begin_date => MusicBrainz::Server::Entity::PartialDate->new_from_row($data->{begin_date}) // {},
            end_date   => MusicBrainz::Server::Entity::PartialDate->new_from_row($data->{end_date}) // {},
            ended      => $data->{ended},
            attributes => [
                map {
                    my $attr = $loaded->{LinkAttributeType}{$_};

                    if ($attr) {
                        my $root_id = $self->c->model('LinkAttributeType')->find_root($attr->id);
                        $attr->root($self->c->model('LinkAttributeType')->get_by_id($root_id));
                        $attr;
                    } else {
                        ();
                    }
                } @{ $data->{attributes} }
            ],
            attribute_text_values => $data->{attribute_text_values} // {},
        ),
        entity0 => $loaded->{$model0}{ $data->{entity0}{id} } ||
            $self->c->model($model0)->_entity_class->new(name => $data->{entity0}{name}),
        entity1 => $loaded->{$model1}{ $data->{entity1}{id} } ||
            $self->c->model($model1)->_entity_class->new(name => $data->{entity1}{name}),
    );
}

sub directly_related_entities {
    my ($self) = @_;

    my $type0 = $self->data->{link_type}{entity0_type};
    my $type1 = $self->data->{link_type}{entity1_type};

    my %result;
    $result{$type0} = [];
    $result{$type1} = [];

    for (@{ $self->data->{relationship_order} }) {
        push @{ $result{$type0} }, $_->{relationship}{entity0}{id};
        push @{ $result{$type1} }, $_->{relationship}{entity1}{id};
    }

    return \%result;
}

sub adjust_edit_pending
{
    my ($self, $adjust) = @_;

    $self->c->model('Relationship')->adjust_edit_pending(
        $self->data->{link_type}{entity0_type},
        $self->data->{link_type}{entity1_type},
        $adjust,
        map { $_->{relationship}{id} } @{ $self->data->{relationship_order} }
    );
}

sub allow_auto_edit { 1 }

sub edit_conditions {
    my $conditions = {
        duration      => 0,
        votes         => 0,
        expire_action => $EXPIRE_ACCEPT,
        auto_edit     => 1,
    };

    return {
        $QUALITY_LOW    => $conditions,
        $QUALITY_NORMAL => $conditions,
        $QUALITY_HIGH   => $conditions,
    };
}

sub initialize {
    my ($self, %opts) = @_;

    my $link_type_id = delete $opts{link_type_id} or die 'Missing link type';
    my $relationship_order = $opts{relationship_order} or die 'Missing relationship order';

    my $lt = $self->c->model('LinkType')->get_by_id($link_type_id);

    $relationship_order = [ grep {
        $_->{old_order} != $_->{new_order}
    } @$relationship_order ];

    my @relationships = map { $_->{relationship} } @$relationship_order;
    $self->c->model('Relationship')->load_entities(@relationships);

    for (@$relationship_order) {
        my $relationship = delete $_->{relationship};
        my $link = $relationship->link;

        die "Relationship link type mismatch" if $link->type_id != $lt->id;

        $_->{relationship} = {
            id => $relationship->id,
            begin_date => partial_date_to_hash($link->begin_date),
            end_date => partial_date_to_hash($link->end_date),
            ended => $link->ended,
            attributes => [ map { $_->id } $link->all_attributes ],
            entity0 => {
                id => $relationship->entity0_id,
                name => $relationship->entity0->name
            },
            entity1 => {
                id => $relationship->entity1_id,
                name => $relationship->entity1->name
            },
            attribute_text_values => $link->attribute_text_values,
        };
    }

    $opts{link_type} = {
        id => $lt->id,
        name => $lt->name,
        link_phrase => $lt->link_phrase,
        reverse_link_phrase => $lt->reverse_link_phrase,
        long_link_phrase => $lt->long_link_phrase,
        entity0_type => $lt->entity0_type,
        entity1_type => $lt->entity1_type,
    };

    $self->data(\%opts);

    return $self;
}

sub build_display_data {
    my ($self, $loaded) = @_;

    return {
        relationships => [
            map +{
                old_order => $_->{old_order},
                new_order => $_->{new_order},
                relationship => $self->_build_relationship($loaded, $_->{relationship}),
            },
            sort { $a->{new_order} <=> $b->{new_order} }
                @{ $self->data->{relationship_order} }
        ]
    };
}

sub accept {
    my $self = shift;

    $self->c->model('Relationship')->reorder(
        $self->data->{link_type}{entity0_type},
        $self->data->{link_type}{entity1_type},
        map { $_->{relationship}{id} => $_->{new_order} } @{ $self->data->{relationship_order} }
    );
}

1;