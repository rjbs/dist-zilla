package Dist::Zilla::Role::PPI;
# ABSTRACT: a role for plugins which use PPI
use Moose::Role;

use Moose::Util::TypeConstraints;

use namespace::autoclean;

use Digest::MD5 qw(md5);
use Storable qw(dclone);

=head1 DESCRIPTION

This role provides some common utilities for plugins which use PPI

=method ppi_document_for_file

  my $document = $self->ppi_document_for_file($file);

Given a dzil file object (anything that does L<Dist::Zilla::Role::File>), this
method returns a new L<PPI::Document> for that file's content.

Internally, this method caches these documents. If multiple plugins want a
document for the same file, this avoids reparsing it.

=cut

my %CACHE;

sub ppi_document_for_file {
  my ($self, $file) = @_;

  my $content = $file->content;

  # We cache on the MD5 checksum to detect if the document has been modified
  # by some other plugin since it was last parsed, our document is invalid.
  my $md5 = md5($content);
  return $CACHE{$md5} if $CACHE{$md5};

  my $document = PPI::Document->new(\$content)
    or Carp::croak(PPI::Document->errstr);

  return $CACHE{$md5} = $document;
}

=method save_ppi_document_to_file

  my $document = $self->save_ppi_document_to_file($document,$file);

Given a L<PPI::Document> and a dzil file object (anything that does
L<Dist::Zilla::Role::File>), this method saves the serialized document in the
file.

It also updates the internal PPI document cache with the new document.

=cut

sub save_ppi_document_to_file {
  my ($self, $document, $file) = @_;

  my $new_content = $document->serialize;

  $CACHE{ md5($new_content) } = $document;

  $file->content($new_content);
}

=method document_assigns_to_variable

  if( $self->ppi_document_for_file($document, '$FOO')) { ... }

This method returns true if the document assigns to the given variable.

=cut

sub document_assigns_to_variable {
  my ($self, $orig_document, $variable) = @_;

  # Clone because ppi_document_for_file which the caller is likely to
  # have retrieved his document from caches aggressively, and we'd
  # like to prun POD and comments.
  #
  # It would be pretty stupid of us to say we found a variable in some
  # comment or in the POD, which we might do because if the POD is
  # preceded by __END__ or __DATA__ it'll be a PPI::Statement. So
  # prune PPI::Statement::* things that we don't want, note that we
  # don't have to prune e.g. PPI::Token::Pod because of the isa check
  # in the finder below.
  my $document = dclone($orig_document);
  $document->prune($_) for qw(PPI::Statement::End PPI::Statement::Data);

  my $finder = sub {
    my $node = $_[1];
    return 1 if $node->isa('PPI::Statement') && $node->content =~ /(?<!\\)\Q$variable\E\s*=/sm;
    return 0;
  };

  my $rv = $document->find_any($finder);
  Carp::croak($document->errstr) unless defined $rv;

  return $rv;
}

1;
