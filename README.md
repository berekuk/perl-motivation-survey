# Perl motivation survey - data, processing scripts and results

HTML report can be found here: <http://berekuk.github.com/perl-motivation-survey/>.

See <http://blogs.perl.org/users/vyacheslav_matjukhin/2012/11/open-source-motivation-survey.html> for the original announcement of this survey.

# Repo contents

This repo includes:
* raw, anonymized results in `data` file
* `process.pl` for processing those results; it generates `results.json` and output them to stdout in human-readable format at the same time
* cached `results` output of the `process.pl`
* `index.html` which loads `results.json` and renders them using Bootstrap and Highcharts

`gh-pages` branch is identical to the `master` branch, so you can see the html report here: <http://berekuk.github.com/perl-motivation-survey/>.

# Data

The raw data is available at the Wufoo website: <http://berekuk.wufoo.eu/reports/perl-motivation-raw-data/>. Note the `Export Data` button.

You can run `REFETCH=1 ./process.pl` to update the `data` file cache from Wufoo.

[![githalytics.com alpha](https://cruel-carlota.pagodabox.com/569c6fee22dbe06156b307a7410368e2 "githalytics.com")](http://githalytics.com/berekuk/perl-motivation-survey)
