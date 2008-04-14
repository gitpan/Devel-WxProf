package Devel::WxProf::Treemap::Output::Imager;
use 5.006;
use strict; use warnings;
use version; our $VERSION = qv(0.0.1);

use Imager;
use Imager::Font;
use Imager::Color;

# ------------------------------------------
# Methods:
# ------------------------------------------
sub new {
   my $class = shift;
   my %args = @_;
   my $self = bless { %args }, $class;
   $self->{WIDTH} = $self->{WIDTH} || 400;
   $self->{HEIGHT} = $self->{HEIGHT} || 300;
   $self->{PADDING} = $self->{PADDING} || 5;
   $self->{SPACING} = $self->{SPACING} || 5;
   $self->{BORDER_COLOUR} = $self->{BORDER_COLOUR} || "#000000";
   $self->{BORDER_COLOUR_3D} = $self->{BORDER_COLOUR_3D} || "#FFFFFF";
   $self->{FONT_COLOUR} = $self->{FONT_COLOUR} || "#000000";
   $self->{MIN_FONT_SIZE} = $self->{MIN_FONT_SIZE} || 5;
   $self->{FONT_FILE} = $self->{FONT_FILE} || "ImUgly.ttf";
   $self->{TEXT_DEBUG} = $self->{TEXT_DEBUG} || 0;
   $self->{DEBUG} = $self->{DEBUG} || 0;

   ##  aggregate resource variables:
   $self->{IMAGE} = Imager->new( xsize    => $self->{WIDTH},
                                 ysize    => $self->{HEIGHT} );
   $self->{ALPHA} = Imager->new();# xsize    => $self->{WIDTH},
                                # ysize    => $self->{HEIGHT},
                                # channels => 4     );

   $self->{DEBUG} && print STDERR "Created a new image object.\n";

   # init cache with border colour and font colours:
   $self->{COLOUR_CACHE} = {
        BORDER_COLOUR => Imager::Color->new($self->{BORDER_COLOUR}),
        BORDER_COLOUR_3D => Imager::Color->new($self->{BORDER_COLOUR_3D}),
   };
   $self->{ALPHA_FONT} = Imager::Color->new( 0, 0, 0, 110 );
   $self->{SOLID_FONT} = Imager::Color->new( $self->{FONT_COLOUR} );

    die "font file not found $self->{FONT_FILE}"
        if ! -r $self->{FONT_FILE};

   $self->{FONT} = Imager::Font->new(
                        file  => $self->{FONT_FILE},
                        color => $self->{SOLID_FONT},
                        aa    => 1,
                        type  => 'ft2',
                        face => 'bold' );

    die "no font" if not $self->{FONT};

    # for profiling:
    $self->{font_iters} = 0;
    return $self;
}

sub save {
   my $self = shift;
   my ( $filename ) = @_;
   $self->{IMAGE}->write( file=>$filename );
   return 1;
}

sub rect {
    my $self = shift;
    my ( $x1, $y1, $x2, $y2, $colour ) = @_;
    my $area = ( $x2 - $x1 ) * ( $y2 - $y1 );

    # cache any colour object that is created; Imager::Color is an expensive
    # operation
    if ( ! $self->{COLOUR_CACHE}->{$colour} )
    {
        $self->{COLOUR_CACHE}->{$colour} = Imager::Color->new( $colour );
    }

    # draw inner box (filled):
    $self->{IMAGE}->box( color  => $self->{COLOUR_CACHE}->{$colour},
                        xmin   => $x1+1,
                        ymin   => $y1+1,
                        xmax   => $x2-1,
                        ymax   => $y2-1,
                        filled => 1      );

    return 1 if ( $area < 3 );

    # draw outer "outline" box (stroked):
    $self->{IMAGE}->box( color  => $self->{COLOUR_CACHE}->{$self->{BORDER_COLOUR}},
                        xmin   => $x1,
                        ymin   => $y1,
                        xmax   => $x2,
                        ymax   => $y2,
                        filled => 0      );

    return 1;
}

## text label drawing method:
# new "guessing" method
# see old method below  -- fishy
sub text {
    my $self = shift;
    my ( $x1, $y1, $x2, $y2, $text, $children ) = @_;

    my $width = abs( $x2 - $x1 );
    my $height = abs( $y2 - $y1 );

    # It's not worth trying to print text in here, it's too narrow
    return 1 if ( $width < 20 );

    # It's not worth trying to print text in here, it's too short
    return 1 if ( $height < 10 );

    my $size = $self->_font_fit( $width, $height, $text );

    return 1 if ( ! $size );

    # try to get a reasonable top-padding, if available:
    #my $top_pad = int(( $height - $metrix[5] ) * 0.1 );
    #$top_pad = ( $top_pad > 5 ) ? 5 : $top_pad;
    #$y = $y1 + $metrix[5] + $top_pad;

    $self->{IMAGE}->string(
                           font  => $self->{FONT},
                           text  => $text,
                           x     => $x1 + 1,
                           y     => $y1 + $size,
                           color => $self->{SOLID_FONT},
                           size  => $size,
                           );
   return 1;
}

## font fitting algorhythm
# moved to seperate function, merged with guessing function
sub _font_fit {
   my $self = shift;
   my ( $width, $height, $text ) = @_;
   my $DEBUG = $self->{TEXT_DEBUG};

   return unless $text && ( length( $text ) ) && $height && $width;

   my $local_iters = 0;

   # Search for suitable font size
   $self->{TEXT_DEBUG} && print STDERR "$text:\n";

   # fetch a guess at the starting point:
   # if not initialized:
   unless ( $self->{ACWPP} )
   {
      # find average character width per point
      $self->{ACWPP} = $self->_calc_avg_char_weight_per_pt();
      croak( "Initialization of font fitting algorhythm failed." )
         unless ( $self->{ACWPP} );
   }

   my $size = int( ( $width / length( $text ) ) / $self->{ACWPP} );

   # because it is guaranteed to be not worth it:
   return if ( $size <= ( $self->{MIN_FONT_SIZE} - 2 ) );
   return $self->{ MAX_FONT_SIZE } if $size > $self->{ MAX_FONT_SIZE };

   # test guess:
   my @metrix = $self->{FONT}->bounding_box(
                                       string => $text,
                                       size   => $size,
                                       canon  => 1       );

   # two corrective measures:

   # 1. if the width fits, but not the height, then we have a height
   # restricted case.  These tend to be expensive, so we "correct" our
   # guess.
   if (( $metrix[2] <= $width ) && ( $metrix[3] > $height )) {
      # if there is a major difference in height, correct guess
      if (( abs( $height - $metrix[3] ) / $height ) * $size >= 3 )
      {
         $self->{font_iters}++; $local_iters++;  # track iterations

         $self->{TEXT_DEBUG} && print STDERR "\tHeight restricted, changing $size =>";
         $size = int( $size * ( $height / $metrix[3] ));
         $self->{TEXT_DEBUG} && print STDERR "$size.\n";

         @metrix = $self->{FONT}->bounding_box(
                                       string => $text,
                                       size   => $size,
                                       canon  => 1       );
      }
   }
   # 2. if our guess is way off width-wise, correct:
   #    if a correction would yeild a size change of more than 3,
   #    it is obviously worth it.
   elsif ( ( abs( $width - $metrix[2] ) / $width ) * $size >= 3 )
   {
      $self->{font_iters}++; $local_iters++;  # track iterations
      $self->{TEXT_DEBUG} && print STDERR "\tOff by 3pts+, changing $size =>";
      $size = int( $size * ( $width / $metrix[2] ));
      $self->{TEXT_DEBUG} && print STDERR "$size.\n";
      @metrix = $self->{FONT}->bounding_box(
                                    string => $text,
                                    size   => $size,
                                    canon  => 1       );
   }

   # if our guess was too large, try smaller values until there is a fit:
   if (( $metrix[2] > $width ) || ( $metrix[3] > $height )) {
      $self->{TEXT_DEBUG} && print STDERR "\tGuess ($size) too large.\n";
      while ( ( $metrix[2] > $width ) || ( $metrix[3] > $height ) )
      {
         $self->{font_iters}++; $local_iters++;  # track iterations
         $size--;

         return if ( $size < 5 );

         @metrix = $self->{FONT}->bounding_box(
                                          string => $text,
                                          size   => $size,
                                          canon  => 1    );
      }
   }
   # if our guess is too small, try larger values until there is a -no- fit:
   elsif ( ( $metrix[2] <= $width ) && ( $metrix[3] <= $height )) {
      $self->{TEXT_DEBUG} && print STDERR "\tGuess ($size) fits, adjusting.\n";
      while ( ( $metrix[2] <= $width ) && ( $metrix[3] <= $height ) )
      {
         $self->{font_iters}++; $local_iters++;  # track iterations

         $size++;
         $size++ if ( $size > 50 );  # grow a bit faster for big fonts

         @metrix = $self->{FONT}->bounding_box(
                                          string => $text,
                                          size   => $size,
                                          canon  => 1    );
      }
      $size--;  # because this overshoots
   }

   $self->{TEXT_DEBUG} && print STDERR "\t$local_iters :: " . $self->{font_iters} . " => $size\n";

   $size = int( $size * 0.9 );  # reduce size to fit comfortably

   return if ( $size < $self->{MIN_FONT_SIZE} );

   return $size;
}

###############################################
#
# private: _calc_avg_char_weight_per_pt
# input:  none
# output: ACWPP
#
#   pardon the size of this function name
#   it only needs to be called in one place
#
sub _calc_avg_char_weight_per_pt {
   my $self = shift;
   my $wieghting_string = "rstlnaei0RST.-";
   my $sample_size = 50;

   # get metrix for sample:
   my @metrix = $self->{FONT}->bounding_box(
                                    string => $wieghting_string,
                                    size   => $sample_size,
                                    canon  => 1         );

   my $sample_width = $metrix[2];
   return unless ( $sample_width );

   # avg    width           per character                 per point
   return ( $sample_width / length( $wieghting_string ) / $sample_size );
}


sub width {
   my $self = shift;
   return $self->{WIDTH};
}

sub height {
   my $self = shift;
   return $self->{HEIGHT};
}

sub font_height {
   my $self = shift;
   return "12";
}

sub padding {
   my $self = shift;
   return $self->{PADDING};
}

sub spacing {
   my $self = shift;
   return $self->{SPACING};
}

1;

__END__

=head1 NAME

Devel::WxProf::Treemap::Output::Imager

=head1 DESCRIPTION

Imager Output for Devel::WxProf::Treemap. Based on L<Treemap::Output::Imager|Treemap::Output::Imager>.


=head1 SEE ALSO

L<Treemap>, L<Treemap::Output>, L<Imager>

=head1 AUTHORS

Martin Kutter E<lt>martin.kutter fen-net.deE<gt>

Based on Treemap by

Simon Ditner <simon@uc.org>, and Eric Maki <eric@uc.org>

=head1 CREDITS

Imager is a very nice image manipulation library written by Arnar M.
Hrafnkelsson (addi@imager.perl.org) and Tony Cook (tony@imager.perl.org).

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut