#!/usr/bin/env perl
=begin comment
  The Ceasar Cipher is a simple rotational cryptographic algorithm.
  However, it is enhanced with the additions of Vigenère modifications.
=cut
use strict;
use warnings;
use Data::Dumper;

sub get_letters {
  my $key = shift;
  my $letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  my @letter_array = split(//, $letters);
  my $idx = index($letters, $key) + 1;
  return substr(@letter_array, $idx, $#letter_array) . substr(@letter_array, 0, $idx - 1);
}

sub generate_matrix {
  my ($code) = @_;
  my $letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  my $index = index($letters, $code);
  my @matrix;

  for my $i (0 .. 25) {
    my $rotated = substr($letters, $index) . substr($letters, 0, $index);
    push @matrix, [ split //, $rotated ];
    $index = ($index + 1) % 26;
  }

  return \@matrix;  # return reference to 2D array
}

sub display_matrix {
  my ($matrix_ref) = @_;
  my @matrix = @$matrix_ref;  # dereference the 2D array reference
  my $letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

  # Print header row
  print "[ ] ";
  for my $ch (split //, $letters) {
    printf " [%s]", $ch;
  }
  print "\n";

  # Print each matrix row
  for my $i (0 .. $#matrix) {
    printf "[%s] ", substr($letters, $i, 1);
    for my $j (0 .. $#{$matrix[$i]}) {
      printf "| %s ", $matrix[$i][$j];
    }
    print "|\n";
  }
}

my $response = get_letters('H');
print $response;
# display_matrix(@response);