#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use LWP::UserAgent;

my @reasons = (
    'Writing the code the way I want',
    'Making the world a better place',
    'Moral satisfaction',
    'Improving the software I use',
    'Learning',
    'Creativity',
    'Socializing',
    'Collaborating with other people',
    'Getting feedback',
    'Getting praise',
    'Building a career',
    'Making money',
    'Job requirement',
);

my @motivation_levels = (
    "Don't care",
    "Weakly motivating",
    "Motivating",
    "Strongly motivating",
    "It discourages me",
    "Doesn't apply",
    "N/A",
);

sub fetch_data {
    my $response = LWP::UserAgent->new->get('http://berekuk.wufoo.eu/export/report/perl-motivation-raw-data.txt');
    die $response->status_line unless $response->is_success;
    return $response->content;
}

sub cleanup_data {
    my $result = shift;

    for (
        # these fields can't be quantified
        'List any other possible reasons for your participation:',
        "Anything else you'd like to share on the topic of this survey:",
        "CPAN ID, if you have one and you're ok with sharing it:",
        # technical fields from wufoo
        "Last Page Accessed",
        "Created By",
        "Updated By",
        "IP Address",
        "Last Updated",
        "Completion Status",
        "Entry Id",
    ) {
        delete $result->{$_} or die "Column '$_' not found";
    }
}

sub load_data {
    my $content = fetch_data();

    my @lines = split /\n/, $content;
    s/\r$// for @lines;

    my $columns_line = shift @lines;
    my @columns = split /\t/, $columns_line;

    my $result = {};
    for my $line (@lines) {
        my @values = split /\t/, $line;

        for my $cid (0 .. $#columns) {
            my $value = $values[$cid];
            $value = 'N/A' if $value eq '';
            push @{ $result->{$columns[$cid]} }, $value;
        }
    }

    # current report doesn't contain any fields that need cleanup
    # but that can change in the future
    # cleanup_data($result);

    return $result;
}

sub print_reason_histogram {
    my $answers = shift;

    my %stat = map { $_ => 0 } @motivation_levels;
    $stat{$_}++ for @$answers;

    $stat{"No answer"} = delete $stat{""} if $stat{""};

    say "$_\t$stat{$_}" for @motivation_levels;
}

sub main {
    my $result = load_data();

    for my $reason (@reasons) {
        say "=== $reason ===";
        print_reason_histogram($result->{$reason});
        say '';
    }
}

main unless caller;
