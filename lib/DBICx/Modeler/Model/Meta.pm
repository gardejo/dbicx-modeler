package DBICx::Modeler::Model::Meta;

use strict;
use warnings;

use Moose;

use DBICx::Modeler::Carp;
use constant TRACE => DBICx::Modeler::Carp::TRACE;

has parent => qw/is ro isa Maybe[DBICx::Modeler::Model::Meta] lazy_build 1/;
sub _build_parent {
    my $self = shift;
    if (my $method = $self->model_class->meta->find_next_method_by_name( 'model_meta' )) {
        return $method->();
    }
    return undef;
}
has model_class => qw/is ro required 1/;
has _specialization => qw/is ro isa HashRef/, default => sub { {} };

sub _specialize_relationship {
    my $self = shift;
    my ($relationship_kind, $relationship_name, $model_class) = @_;
    $self->_specialization->{relationship}->{$relationship_name} = {
            kind => $relationship_kind,
            name => $relationship_name,
            model_class => $model_class,
    };
}

sub belongs_to {
    my $self = shift;
    $self->_specialize_relationship( belongs_to => @_ );
}

sub has_one {
    my $self = shift;
    $self->_specialize_relationship( has_one => @_ );
}

sub has_many {
    my $self = shift;
    $self->_specialize_relationship( has_many => @_ );
}

sub might_have {
    my $self = shift;
    $self->_specialize_relationship( might_have => @_ );
}

sub specialize_model_source {
    my $self = shift;
    my $model_source = shift;
    if ( local $_ = $self->_specialization->{relationship} ) {
        for my $specialized_relationship (values %$_) {
            my ($name, $kind, $model_class) = @$specialized_relationship{qw/ name kind model_class /};
            my $relationship = $model_source->relationship( $name );
            DBICx::Modeler->ensure_class_loaded( $model_class );
            $relationship->model_class( $model_class );
        }
    }
    return $model_source;
}

sub initialize_base_model_class {
    my $self = shift;
    my $model_source = shift;

    # $model_source should have been specialized already
    croak "I should only be called on base model classes" if $self->parent;

    my $meta = $self->model_class->meta;
    my $result_source = $model_source->result_source;

    for my $relationship ( $model_source->relationships ) {
        my $name = $relationship->name;

        next if $meta->has_method($name);

        if (! $relationship->is_many) {
            $meta->add_attribute( $name => qw/is ro lazy 1/, default => sub {
                my $self = shift;
                return $self->model_source->inflate_related( $self, $name );
            } );
        }
        else {
            $meta->add_method( $name => sub {
                my $self = shift;
                return $self->model_source->search_related( $self, $name, @_ );
            } );
        }
    }

    my $attribute;
    if ($attribute = $meta->get_attribute( 'model_storage' )) {

        if ($attribute->has_handles) { 
            # Assume the user know's what they're doing
            # TODO Add a TRACE here
        }
        else {
            my @handles = grep { ! $meta->has_method( $_ ) } $result_source->columns;
            my $new_attribute = $meta->_process_inherited_attribute( $attribute->name, handles => \@handles );
            $meta->add_attribute( $new_attribute );
        }
    }
    else {
        croak $self->model_class, ' WTF?';
        # TODO Warn we don't know what's going on
    }
}

1;