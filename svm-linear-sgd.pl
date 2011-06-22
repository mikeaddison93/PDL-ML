#!/usr/bin/perl

# SVM example - stochastic (sub)gradient descent for linear SVMs

# Get example dataset with
# wget http://www.csie.ntu.edu.tw/~cjlin/libsvmtools/datasets/binary/heart_scale

# (c) 2011 Zeno Gantner
# License: GPL

# TODO
#  - learn rate schedule
#  - use more PDL features to speed up computation
#  - implement stopping criterion as in lecture slides

use strict;
use warnings;
use 5.10.1;

use English qw( -no_match_vars );
use Getopt::Long;
use List::Util;
use PDL;
use PDL::LinearAlgebra;
use PDL::NiceSlice;

GetOptions(
	   'help'              => \(my $help            = 0),
	   'verbose'           => \(my $verbose         = 0),
	   'compute-fit'       => \(my $compute_fit     = 0),
	   'epsilon=f'         => \(my $epsilon         = 0.1),
	   'training-file=s'   => \(my $training_file   = ''),
	   'test-file=s'       => \(my $test_file       = ''),
	   'prediction-file=s' => \(my $prediction_file = ''),
	   'regularization=f'  => \(my $regularization  = 0.01),
	   'learn-rate=f'      => \(my $learn_rate      = 0.001),
	   'num-iter=i'        => \(my $num_iter        = 10),
	  ) or usage(-1);

usage(0) if $help;


if ($training_file eq '') {
        say "Please give --training-file=FILE";
        usage(-1);
}

my ( $instances, $targets ) = convert_to_pdl(read_data($training_file));
my $num_instances = (dims $instances)[0];
my $num_features  = (dims $instances)[1];

# solve optimization problem
my ($bias, $beta) = sgd($instances, $targets);
# prepare prediction function
my $predict = sub { return $bias + $beta x $_[0] <=> 0; };
my $predict_several = sub {
        my ($instances) = @_;        
        my $num_instances = (dims $instances)[0];
        
        my $predictions = zeros($num_instances);
        for (my $i = 0; $i < $num_instances; $i++) {
                $predictions($i) .= $bias + $beta x $instances($i) <=> 0;
        }
        
        return $predictions;
};

# compute fit
if ($compute_fit) {
        my $pred = &$predict_several($instances);

        say $pred;
        say $targets;

        my $fit_err  = sum(abs($pred - $targets));
        say $fit_err;
        $fit_err /= $num_instances;

        say "FIT_ERR $fit_err N $num_instances";
}

# test/write out predictions
if ($test_file) {
        my ( $test_instances, $test_targets ) = convert_to_pdl(read_data($test_file));
        my $test_pred = &$predict_several($test_instances);

        if ($prediction_file) {
                write_vector($test_pred, $prediction_file);
        }
        else {
                my $num_test_instances = (dims $test_instances)[0];

                my $test_err  = sum(abs($test_pred - $test_targets));
                $test_err /= $num_test_instances;
                say "ERR $test_err N $num_test_instances";
        }
}

exit 0;

# TODO better name?
sub min_max {
        my ($x, $a, $b) = @_;
        
        return $x if $x > $a && $x < $b;
        return $a if $a >= $x && $a < $b;
        return $b;
}

# solve primal optimization problem
sub sgd {
        my ($x, $y) = @_;

        my $bias = 0;
        my $beta = zeros $num_features;
        
        for (my $i = 0; $i < $num_iter * $num_instances; $i++) {
                my $index = rand($num_instances - 1);

                if ($y($index) * ($bias + $beta x $instances($index)) < 1) {
                        my $diff_beta = $y($index) * $instances($index)->transpose;
                        my $diff_bias = $y($index);
                        
                        $beta = (1 - $learn_rate * $regularization) * $beta + $learn_rate * $diff_beta;
                        $bias -= $learn_rate * $diff_bias;
                }
        }

        return ($bias, $beta);
}

# convert Perl data structure to piddles
sub convert_to_pdl {
        my ($data_ref, $num_features) = @_;

        my $instances = zeros scalar @$data_ref, $num_features;
        my $targets   = zeros scalar @$data_ref; # TODO handle multi-class/multi-label here

        for (my $i = 0; $i < scalar @$data_ref; $i++) {
                my ($feature_value_ref, $target) = @{ $data_ref->[$i] };

                $targets($i) .= $target;

                foreach my $id (keys %$feature_value_ref) {
                        $instances($i, $id) .= $feature_value_ref->{$id};
                }
        }

        return ( $instances, $targets );
}

# read LIBSVM-formatted data from file
sub read_data {
        my ($training_file) = @_;

        my @labeled_instances = ();

        my $num_features = 0;

        open my $fh, '<', $training_file;
        while (<$fh>) {
                my $line = $_;
                chomp $line;

                my @tokens = split /\s+/, $line;
                my $label = shift @tokens;               
                $label = -1 if $label == 0;
                
                die "Label must be 1/0/-1, but is $label\n" if $label != -1 && $label != 1;

                my %feature_value = map { split /:/ } @tokens;
                $num_features = List::Util::max(keys %feature_value, $num_features);

                push @labeled_instances, [ \%feature_value, $label ];
        }
        close $fh;

        $num_features++; # take care of features starting index 0

        return (\@labeled_instances, $num_features); # TODO named return
}

# write row vector to text file, one line per entry
sub write_vector {
        my ($vector, $filename) = @_;
        open my $fh, '>', $filename;
        foreach my $col (0 .. (dims $vector)[0] - 1) {
                say $fh $vector->at($col, 0);
        }
        close $fh;
}


sub usage {
    my ($return_code) = @_;

    print << "END";
$PROGRAM_NAME

Perl Data Language SVM example: stochastic subgradient descent for linear SVMs

usage: $PROGRAM_NAME [OPTIONS] [INPUT]

    --help                  display this usage information
    --verbose               show diagnostic/progress output
    --epsilon=NUM           set convergence sensitivity to NUM
    --compute-fit           compute error on training data
    --training-file=FILE    read training data from FILE
    --test-file=FILE        evaluate on FILE
    --prediction-file=FILE  write predictions for instances in the test file to FILE
    --regularization=NUM    regularization parameter C
    --learn-rate=NUM        
    --num-iter=N            number of passes over the training data
END
    exit $return_code;
}