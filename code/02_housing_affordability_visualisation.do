clear all
set more off


* ============================================================
* HOUSING AFFORDABILITY PROJECT
* VISUALISATION
* ============================================================


* ============================================================
* 1. PROJECT FOLDERS AND LOG
* ============================================================

* This GitHub version uses relative paths.
*
* IMPORTANT:
* Run this do-file with Stata's working directory set to the
* repository root:
*
* housing-affordability-england-wales/
global project "."

global output ///
"$project/output"

global derived ///
"$output/derived_data"

global figures ///
"$project/figures"


* Create output folders if they do not already exist.
capture mkdir "$output"
capture mkdir "$figures"


* Close any old log that may still be open.
capture log close

* Record the visualisation run separately from the analysis log.
log using ///
"$output/housing_affordability_visualisation.log", ///
text replace


* ============================================================
* 2. LOAD THE FINAL ANALYSIS DATASET
* ============================================================

* The visualisation file depends on the final dataset produced
* by 01_housing_affordability_analysis.do.
capture confirm file ///
"$derived/housing_affordability_analysis_2015_2025.dta"

if _rc {
    display as error ///
    "Final analysis dataset not found. Run code/01_housing_affordability_analysis.do first."

    exit 601
}


use ///
"$derived/housing_affordability_analysis_2015_2025.dta", ///
clear


* Confirm the expected panel structure.
isid geography_code year


* ============================================================
* 3. CHART 1: MEDIAN AFFORDABILITY OVER TIME
* ============================================================

* We temporarily reduce the panel dataset to one observation
* per year.
*
* collapse calculates the median affordability ratio across
* local authorities for each year.

preserve

collapse (median) affordability_ratio, ///
    by(year)


* Create a line chart.
*
* Higher values mean that median house prices are larger
* relative to median annual earnings, so housing is less
* affordable.

twoway ///
    (connected affordability_ratio year, sort), ///
    title("Housing affordability in England and Wales") ///
    subtitle("Median house-price-to-earnings ratio, 2015-2025") ///
    xtitle("Year") ///
    ytitle("Median house-price-to-earnings ratio") ///
    xlabel(2015(1)2025, angle(45)) ///
    ylabel(, angle(horizontal)) ///
    legend(off) ///
    note("2025 earnings are provisional.")


* Save the chart as an image.
graph export ///
"$figures/affordability_trend.png", ///
replace width(2400)


* Return to the full authority-year dataset.
restore


* ============================================================
* 4. CHART 2: HOUSE-PRICE GROWTH VS EARNINGS GROWTH
* ============================================================

preserve


* Endpoint growth is repeated across the yearly rows of each
* authority.
*
* Keep only one observation per local authority.
keep if analysis_authority_tag == 1


* Both growth measures must be available.
drop if missing(house_price_growth, earnings_growth)


* Scatter plot:
*
* X-axis = earnings growth
* Y-axis = house-price growth
*
* The dashed diagonal represents equal growth:
* house-price growth = earnings growth.
*
* Points ABOVE the line:
* house prices grew faster than earnings.
*
* Points BELOW the line:
* earnings grew faster than house prices.

twoway ///
    (scatter house_price_growth earnings_growth, ///
        msize(small)) ///
    (function y=x, ///
        range(-10 100) ///
        lpattern(dash)), ///
    title("House-price growth versus earnings growth") ///
    subtitle("Local authorities, 2015-2025") ///
    xtitle("Median earnings growth (%)") ///
    ytitle("Median house-price growth (%)") ///
    xscale(range(-10 100)) ///
    yscale(range(-10 100)) ///
    xlabel(-10(10)100) ///
    ylabel(-10(10)100, angle(horizontal)) ///
    aspectratio(1) ///
    legend(order(1 "Local authorities" 2 "Equal growth")) ///
    note("2025 earnings are provisional.")


graph export ///
"$figures/price_vs_earnings_growth.png", ///
replace width(2400)


restore


* ============================================================
* 5. CHART 3: LEAST AFFORDABLE AREAS IN 2025
* ============================================================

preserve


* Keep only the latest year.
keep if year == 2025


* Affordability cannot be ranked when earnings are missing.
drop if missing(affordability_ratio)


* Sort from highest ratio to lowest ratio.
*
* Higher ratio = less affordable relative to local earnings.
gsort -affordability_ratio


* Keep the ten highest ratios.
keep in 1/10


* Horizontal bars work well because local-authority names
* can be relatively long.

graph hbar (asis) affordability_ratio, ///
    over(geography_name, ///
        sort(1) ///
        descending ///
        label(labsize(small))) ///
    title("Least affordable local authorities in 2025") ///
    subtitle("Median house price relative to median annual earnings") ///
    ytitle("House-price-to-earnings ratio") ///
    blabel(bar, format(%4.1f)) ///
    legend(off) ///
    note("2025 earnings are provisional.")


graph export ///
"$figures/least_affordable_2025.png", ///
replace width(2400)


restore



* ============================================================
* 6. CHART 4: MOST AFFORDABLE AREAS IN 2025
* ============================================================

preserve

keep if year == 2025

drop if missing(affordability_ratio)


* Sort from lowest ratio to highest.
sort affordability_ratio


* Keep the ten lowest ratios.
keep in 1/10


graph hbar (asis) affordability_ratio, ///
    over(geography_name, ///
        sort(1) ///
        label(labsize(small))) ///
    title("Most affordable local authorities in 2025") ///
    subtitle("Median house price relative to median annual earnings") ///
    ytitle("House-price-to-earnings ratio") ///
    blabel(bar, format(%4.1f)) ///
    legend(off) ///
    note("2025 earnings are provisional.")


graph export ///
"$figures/most_affordable_2025.png", ///
replace width(2400)


restore


* ============================================================
* END VISUALISATION LOG
* ============================================================

log close
