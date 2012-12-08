# Perl motivation survey - data, processing scripts and results

See <http://blogs.perl.org/users/vyacheslav_matjukhin/2012/11/open-source-motivation-survey.html> for the original announcement of this survey.

# Contents

This repo will include:
* anonymized results
* scripts for processing these results
* html/pdf with histograms and other aggregated data

# Data

The raw, anonymized data can be found here: <http://berekuk.wufoo.eu/reports/perl-motivation-raw-data/>. Use the "export" button to get the tab-separated data for further processing.

Cached copy of the data is stored in this repo, in the `data` file.

# Scripts

`process.pl` processes the data and prints the aggregated results to the terminal.

It can fetch the latest version of data with `REFETCH=1` option. It'll use the `data` file otherwise.

Ideas on different metrics to calculate:
* how the experience and contribution frequency slices affect the reasons?
* correlations between different motivations
* are there reasons that are more important than other reasons for the most people (i.e., "Getting feedback" > "Getting praise" for 90%)?

# HTML/PDF

TBD. I hope `process.pl` will generate them.

[![githalytics.com alpha](https://cruel-carlota.pagodabox.com/569c6fee22dbe06156b307a7410368e2 "githalytics.com")](http://githalytics.com/berekuk/perl-motivation-survey)
