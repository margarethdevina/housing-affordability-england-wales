clear all
set more off


* ============================================================
* PROJECT: HOUSING AFFORDABILITY IN ENGLAND AND WALES
* PERIOD: 2015-2025
*
* Main question:
* How have local house prices changed relative to the earnings
* of residents across consistently matched local authorities?
*
* Main sources:
* - ONS Annual Survey of Hours and Earnings (ASHE)
* - ONS / HM Land Registry median price paid data
*
* Main measure:
* Median house price / median annual full-time earnings
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
*
* Using "." makes the project portable across computers.
global project "."

* Original source-data folders.
global earnings ///
"$project/data/earnings"

global houseprices ///
"$project/data/house_prices"

* Generated outputs are kept separate from the original data.
global output ///
"$project/output"

global derived ///
"$output/derived_data"

* Create generated-output folders if they do not already exist.
capture mkdir "$output"
capture mkdir "$derived"

* Close any old log that may still be open.
capture log close

* Record all commands and Stata output from this run.
log using ///
"$output/housing_affordability_analysis.log", ///
text replace



* ============================================================
* STEP 1: PREPARE ANNUAL EARNINGS DATA
* ============================================================


* ============================================================
* 2. FIND ALL 2015-2025 EARNINGS FILES
* ============================================================

* Find every .xls or .xlsx file containing
* "Annual pay - Gross" in the filename.
*
* This allows the annual files to be processed automatically
* instead of importing each year manually.
local files : dir "$earnings" files "*Annual pay - Gross*.xls*"

* Show which files Stata found.
display `"`files'"'



* ============================================================
* 3. COMBINE THE ANNUAL EARNINGS FILES
* ============================================================

* Temporary dataset used while annual files are combined.
tempfile earnings_master

* first = 1 means no annual file has yet been saved.
local first = 1


foreach file of local files {

    display "================================================"
    display "Importing earnings file: `file'"
    display "================================================"


    * --------------------------------------------------------
    * 3A. IDENTIFY THE YEAR FROM THE FILENAME
    * --------------------------------------------------------

    * regexm() checks whether the filename contains a
    * four-digit year beginning with 20.
    *
    * Example:
    * "... Gross 2019.xls" -> match found.
    if regexm("`file'", "(20[0-9][0-9])") {

        * regexs(1) returns the year that regexm() found.
        local year = regexs(1)
    }

    else {

        * Stop rather than silently assigning the wrong year.
        display as error ///
        "Could not identify the year in file: `file'"

        exit 198
    }


    * --------------------------------------------------------
    * 3B. IMPORT THE FULL-TIME WORKSHEET
    * --------------------------------------------------------

    * The useful table begins at cell A5.
    *
    * allstring imports all fields as text first.
    * This preserves ONS values such as "x", which are used
    * when an estimate has been suppressed.
    import excel using "$earnings/`file'", ///
        sheet("Full-Time") ///
        cellrange(A5) ///
        firstrow ///
        allstring ///
        clear


    * --------------------------------------------------------
    * 3C. CHECK THAT REQUIRED VARIABLES EXIST
    * --------------------------------------------------------

    * confirm variable checks that the expected column exists.
    *
    * capture prevents Stata stopping immediately if it does not.
    * _rc then records whether the check produced an error.

    capture confirm variable Description

    if _rc {
        display as error ///
        "Description variable not found in `file'"

        exit 111
    }


    capture confirm variable Code

    if _rc {
        display as error ///
        "Code variable not found in `file'"

        exit 111
    }


    capture confirm variable Median

    if _rc {
        display as error ///
        "Median variable not found in `file'"

        exit 111
    }


    * --------------------------------------------------------
    * 3D. KEEP AND RENAME THE VARIABLES NEEDED
    * --------------------------------------------------------

    keep Description Code Median

    rename Description geography_name
    rename Code        geography_code

    * Preserve the original ONS earnings value.
    *
    * Example:
    * "35446" remains "35446"
    * "x" remains "x"
    rename Median median_annual_pay_raw


    * Remove unnecessary leading/trailing spaces.
    replace geography_name = strtrim(geography_name)
    replace geography_code = strtrim(geography_code)


    * --------------------------------------------------------
    * 3E. CREATE YEAR AND PROVISIONAL STATUS
    * --------------------------------------------------------

    * local year is currently text such as "2019".
    * real() converts it into numeric 2019.
    gen year = real("`year'")

    * The 2025 earnings file is provisional.
    gen provisional = (year == 2025)


    * --------------------------------------------------------
    * 3F. CREATE NUMERIC EARNINGS
    * --------------------------------------------------------

    * Convert valid text numbers into numeric values.
    *
    * Non-numeric values such as "x" become numeric missing (.).
    * The original value is retained in median_annual_pay_raw.
    destring median_annual_pay_raw, ///
        generate(median_annual_pay) ///
        force


    * --------------------------------------------------------
    * 3G. REMOVE ROWS WITHOUT A USABLE GEOGRAPHY CODE
    * --------------------------------------------------------

    * These rows cannot later be matched reliably with
    * house-price data.
    drop if missing(geography_code)


    * --------------------------------------------------------
    * 3H. ADD THIS YEAR TO THE COMBINED DATASET
    * --------------------------------------------------------

    if `first' == 1 {

        * First annual file creates the temporary master.
        save `earnings_master', replace

        local first = 0
    }

    else {

        * Later years are added underneath the current data.
        append using `earnings_master'

        save `earnings_master', replace
    }
}



* ============================================================
* 4. LOAD THE COMPLETE EARNINGS DATASET
* ============================================================

use `earnings_master', clear

sort geography_code year



* ============================================================
* 5. BASIC EARNINGS CHECKS
* ============================================================

describe

* Confirm all years are present.
tab year

* Confirm only 2025 is marked provisional.
tab year provisional



* ============================================================
* 6. CHECK MISSING AND SUPPRESSED EARNINGS
* ============================================================

* 0 = usable numeric earnings
* 1 = no usable numeric earnings
gen missing_pay = missing(median_annual_pay)


* Compare missingness across years.
tab year missing_pay, row


* Inspect the original ONS values that became numeric missing.
tab median_annual_pay_raw ///
    if missing_pay == 1, ///
    missing


* Confirm geography + year uniquely identify observations.
isid geography_code year



* ============================================================
* 7. IDENTIFY WHY EARNINGS ARE MISSING
* ============================================================

* ONS "x" values are recorded separately as suppressed.
gen pay_suppressed = ///
    lower(strtrim(median_annual_pay_raw)) == "x"


* Blank source cells are identified separately.
gen pay_blank = ///
    strtrim(median_annual_pay_raw) == ""


* Check that missing numeric observations are explained.
tab missing_pay pay_suppressed, missing
tab missing_pay pay_blank, missing


* Inspect blank observations.
list geography_name ///
     geography_code ///
     year ///
     median_annual_pay_raw ///
     if pay_blank == 1, ///
     noobs clean



* ============================================================
* 8. OPTIONAL DIAGNOSTIC: SAMPLE OF MISSING EARNINGS
* ============================================================

* Temporarily keep only missing earnings so that "in 1/30"
* really means the first 30 missing observations.

preserve

keep if missing_pay == 1

list geography_name ///
     geography_code ///
     year ///
     median_annual_pay_raw ///
     median_annual_pay ///
     in 1/30, ///
     noobs clean

restore



* ============================================================
* 9. SAVE THE GENERATED CLEANED EARNINGS DATASET
* ============================================================

* This retains all geographic levels before the analysis
* is restricted to local authorities.
save ///
"$derived/earnings_2015_2025.dta", ///
replace



* ============================================================
* 10. IDENTIFY LOCAL AUTHORITIES
* ============================================================

* Geography codes contain information about geography type.
* The first three characters identify the broad code family.
gen geography_prefix = ///
    substr(geography_code, 1, 3)


* Inspect the geography types in the source.
tab geography_prefix



* ============================================================
* 11. FLAG LOCAL AUTHORITIES
* ============================================================

* Local-authority code families used in this project:
*
* E06 = English unitary authorities
* E07 = English non-metropolitan districts
* E08 = English metropolitan districts
* E09 = London boroughs
* W06 = Welsh unitary authorities

gen is_local_authority = ///
    inlist(geography_prefix, ///
           "E06", "E07", "E08", "E09", "W06")

tab is_local_authority



* ============================================================
* 12. LABEL LOCAL-AUTHORITY TYPES
* ============================================================

* Allocate enough string space from the beginning so Stata
* does not repeatedly enlarge the variable.
gen str33 local_authority_type = ""

replace local_authority_type = ///
    "English unitary authority" ///
    if geography_prefix == "E06"

replace local_authority_type = ///
    "English non-metropolitan district" ///
    if geography_prefix == "E07"

replace local_authority_type = ///
    "English metropolitan district" ///
    if geography_prefix == "E08"

replace local_authority_type = ///
    "London borough" ///
    if geography_prefix == "E09"

replace local_authority_type = ///
    "Welsh unitary authority" ///
    if geography_prefix == "W06"

tab local_authority_type ///
    if is_local_authority == 1



* ============================================================
* 13. KEEP LOCAL AUTHORITIES
* ============================================================

keep if is_local_authority == 1

* Number of local-authority observations by year.
tab year

* Check authority types retained.
tab local_authority_type

* Area + year must remain unique.
isid geography_code year



* ============================================================
* 14. RECHECK EARNINGS QUALITY AFTER GEOGRAPHY FILTER
* ============================================================

* Recalculate the relevant missingness summary for the
* actual local-authority dataset used by the project.
tab year missing_pay, row

count if pay_suppressed == 1
count if pay_blank == 1

list geography_name ///
     geography_code ///
     year ///
     if pay_blank == 1, ///
     noobs clean



* ============================================================
* 15. SUMMARISE EARNINGS COVERAGE BY LOCAL AUTHORITY
* ============================================================

* Count usable earnings years for each authority.
bysort geography_code: egen years_with_pay = ///
    total(!missing(median_annual_pay))


* Count how many years each authority appears in the data.
bysort geography_code: gen years_observed = _N


* Share of observed years with usable earnings.
gen pay_coverage_rate = ///
    years_with_pay / years_observed


* Tag one row per authority so summaries count authorities,
* not repeated area-year observations.
egen authority_tag = tag(geography_code)


* Distribution of usable earnings years by authority.
tab years_with_pay ///
    if authority_tag == 1


* Distribution of years observed by authority.
tab years_observed ///
    if authority_tag == 1


* Overall coverage rate across authorities.
summarize pay_coverage_rate ///
    if authority_tag == 1


* Diagnostic only:
* authorities with less than 80% usable earnings coverage.
list geography_name ///
     geography_code ///
     years_observed ///
     years_with_pay ///
     pay_coverage_rate ///
     if authority_tag == 1 ///
     & pay_coverage_rate < 0.80, ///
     noobs clean



* ============================================================
* 16. SAVE GENERATED LOCAL-AUTHORITY EARNINGS DATA
* ============================================================

sort geography_code year

save ///
"$derived/earnings_local_authorities_2015_2025.dta", ///
replace



* ============================================================
* STEP 2: PREPARE HOUSE-PRICE DATA
* ============================================================


* ============================================================
* 17. IMPORT THE LOCAL-AUTHORITY HOUSE-PRICE TABLE
* ============================================================

* ONS Table 2a contains median price paid by local authority.
*
* The workbook reports rolling annual prices quarterly.
* We use Year Ending September for each year because this
* aligns the annual housing period with the ASHE earnings year.

import excel using ///
"$houseprices/medianpricepaidforadministrativegeographies.xlsx", ///
sheet("2a") ///
cellrange(A1:DT321) ///
allstring ///
clear



* ============================================================
* 18. KEEP THE VARIABLES NEEDED FOR THE ANALYSIS
* ============================================================

* A-D identify the geography.
*
* Annual price columns used:
*
* CF = Year ending Sep 2015
* CJ = Year ending Sep 2016
* CN = Year ending Sep 2017
* CR = Year ending Sep 2018
* CV = Year ending Sep 2019
* CZ = Year ending Sep 2020
* DD = Year ending Sep 2021
* DH = Year ending Sep 2022
* DL = Year ending Sep 2023
* DP = Year ending Sep 2024
* DT = Year ending Sep 2025

keep A B C D ///
     CF CJ CN CR CV CZ ///
     DD DH DL DP DT



* ============================================================
* 19. RENAME HOUSE-PRICE VARIABLES
* ============================================================

rename A region_code
rename B region_name
rename C geography_code
rename D geography_name

rename CF house_price2015
rename CJ house_price2016
rename CN house_price2017
rename CR house_price2018
rename CV house_price2019
rename CZ house_price2020
rename DD house_price2021
rename DH house_price2022
rename DL house_price2023
rename DP house_price2024
rename DT house_price2025



* ============================================================
* 20. KEEP VALID LOCAL-AUTHORITY ROWS
* ============================================================

replace region_code    = strtrim(region_code)
replace region_name    = strtrim(region_name)
replace geography_code = strtrim(geography_code)
replace geography_name = strtrim(geography_name)


gen geography_prefix = ///
    substr(geography_code, 1, 3)


* Apply the same local-authority definition used for earnings.
keep if inlist(geography_prefix, ///
    "E06", "E07", "E08", "E09", "W06")


* In wide format, each geography code should occur once.
isid geography_code



* ============================================================
* 21. RESHAPE HOUSE PRICES FROM WIDE TO LONG
* ============================================================

* Before reshape:
*
* authority | 2015 price | 2016 price | ...
*
* After reshape:
*
* authority | year | price

reshape long house_price, ///
    i(geography_code) ///
    j(year)

sort geography_code year



* ============================================================
* 22. CREATE NUMERIC HOUSE-PRICE VARIABLE
* ============================================================

* Preserve the source value before numeric conversion.
rename house_price median_house_price_raw


* Convert source text into numeric house prices.
destring median_house_price_raw, ///
    generate(median_house_price) ///
    ignore(",") ///
    force



* ============================================================
* 23. CHECK HOUSE-PRICE DATA QUALITY
* ============================================================

gen missing_house_price = ///
    missing(median_house_price)


* Availability by year.
tab year missing_house_price, row


* Inspect original source values if any price becomes missing.
tab median_house_price_raw ///
    if missing_house_price == 1, ///
    missing


* One row per authority-year.
isid geography_code year


* Basic annual reasonableness check.
tabstat median_house_price, ///
    by(year) ///
    statistics(count median mean min max)



* ============================================================
* 24. SAVE GENERATED CLEAN HOUSE-PRICE DATA
* ============================================================

sort geography_code year

save ///
"$derived/house_prices_local_authorities_2015_2025.dta", ///
replace



* ============================================================
* STEP 3: COMBINE HOUSE PRICES AND EARNINGS
* ============================================================


* ============================================================
* 25. MERGE HOUSE PRICES WITH EARNINGS
* ============================================================

* The clean house-price data are still in memory.
*
* Match using:
* geography_code + year

merge 1:1 geography_code year using ///
"$derived/earnings_local_authorities_2015_2025.dta", ///
keepusing( ///
    median_annual_pay_raw ///
    median_annual_pay ///
    missing_pay ///
    pay_suppressed ///
    pay_blank ///
    provisional ///
    local_authority_type ///
)



* ============================================================
* 26. CHECK THE MERGE
* ============================================================

* _merge = 1 -> house price only
* _merge = 2 -> earnings only
* _merge = 3 -> successful match

tab _merge

tab year _merge



* ============================================================
* 27. INSPECT UNMATCHED LOCAL AUTHORITIES
* ============================================================

* Geography reorganisations can create unmatched historical
* codes, so we inspect them before filtering.

preserve

keep if _merge != 3

contract geography_name ///
         geography_code ///
         _merge

rename _freq unmatched_years

sort _merge geography_name

list geography_name ///
     geography_code ///
     _merge ///
     unmatched_years, ///
     sepby(_merge) ///
     noobs clean

restore



* ============================================================
* 28. SAVE THE GENERATED PRE-FILTER MERGE AUDIT DATASET
* ============================================================

save ///
"$derived/housing_earnings_merge_check_2015_2025.dta", ///
replace



* ============================================================
* STEP 4: CREATE A CONSISTENT GEOGRAPHY SAMPLE
* ============================================================


* ============================================================
* 29. IDENTIFY AUTHORITIES MATCHED IN ALL 11 YEARS
* ============================================================

* 1 = price and earnings records matched.
gen matched_record = (_merge == 3)


* Count successful matched years for each code.
bysort geography_code: egen years_matched = ///
    total(matched_record)


* Tag each geography code once.
egen stable_authority_tag = ///
    tag(geography_code)


* Inspect how many codes have 11 successful years.
tab years_matched ///
    if stable_authority_tag == 1



* ============================================================
* 30. KEEP THE CONSISTENT 2015-2025 SAMPLE
* ============================================================

* Keep codes that successfully match for every year.
*
* This avoids comparing different historical authority
* structures as though they were the same geography.
keep if years_matched == 11


* All remaining records should now be matched.
tab _merge


* There should be the same number of authorities each year.
tab year


* Authority + year remains unique.
isid geography_code year


* Tag one row per authority for later summaries.
egen analysis_authority_tag = ///
    tag(geography_code)


* Number of unique consistently matched authorities.
count if analysis_authority_tag == 1



* ============================================================
* STEP 5: CALCULATE HOUSING AFFORDABILITY
* ============================================================


* ============================================================
* 31. CALCULATE THE AFFORDABILITY RATIO
* ============================================================

* Affordability ratio:
*
* median house price / median annual full-time earnings
*
* Example:
* £200,000 / £40,000 = 5
*
* Interpretation:
* the median house costs five times annual median earnings.

gen affordability_ratio = ///
    median_house_price / median_annual_pay ///
    if !missing(median_house_price, median_annual_pay)


label variable affordability_ratio ///
    "Median house price / median annual earnings"



* ============================================================
* 32. CHECK AFFORDABILITY DATA AVAILABILITY
* ============================================================

gen missing_affordability = ///
    missing(affordability_ratio)


tab year missing_affordability, row


* Annual distribution.
tabstat affordability_ratio, ///
    by(year) ///
    statistics(count median mean min max)



* ============================================================
* 33. CHECK EXTREME AFFORDABILITY VALUES
* ============================================================

summarize affordability_ratio, detail


* Threshold >20 is for inspection only.
* No observations are removed.
list geography_name ///
     year ///
     median_house_price ///
     median_annual_pay ///
     affordability_ratio ///
     if affordability_ratio > 20 ///
     & !missing(affordability_ratio), ///
     sepby(year) ///
     noobs clean



* ============================================================
* 34. SUMMARISE PRICES, EARNINGS AND AFFORDABILITY BY YEAR
* ============================================================

tabstat ///
    median_house_price ///
    median_annual_pay ///
    affordability_ratio, ///
    by(year) ///
    statistics(count median mean)



* ============================================================
* 35. INSPECT 2025 AFFORDABILITY EXTREMES
* ============================================================

preserve

keep if year == 2025

drop if missing(affordability_ratio)


* Highest ratios = least affordable relative to earnings.
gsort -affordability_ratio

display ///
"TEN HIGHEST AFFORDABILITY RATIOS IN 2025"

list geography_name ///
     median_house_price ///
     median_annual_pay ///
     affordability_ratio ///
     in 1/10, ///
     noobs clean


* Lowest ratios = more affordable relative to earnings.
sort affordability_ratio

display ///
"TEN LOWEST AFFORDABILITY RATIOS IN 2025"

list geography_name ///
     median_house_price ///
     median_annual_pay ///
     affordability_ratio ///
     in 1/10, ///
     noobs clean

restore



* ============================================================
* STEP 6: ANALYSE 2015-2025 GROWTH
* ============================================================


* ============================================================
* 36. CREATE 2015 AND 2025 ENDPOINT VALUES
* ============================================================

* egen + cond() finds the value for a specific year
* within each local authority and copies it across that
* authority's rows.

bysort geography_code: egen house_price_2015 = ///
    max(cond(year == 2015, median_house_price, .))

bysort geography_code: egen house_price_2025 = ///
    max(cond(year == 2025, median_house_price, .))


bysort geography_code: egen earnings_2015 = ///
    max(cond(year == 2015, median_annual_pay, .))

bysort geography_code: egen earnings_2025 = ///
    max(cond(year == 2025, median_annual_pay, .))



* ============================================================
* 37. CALCULATE HOUSE-PRICE AND EARNINGS GROWTH
* ============================================================

gen house_price_growth = ///
    100 * ((house_price_2025 / house_price_2015) - 1) ///
    if !missing(house_price_2015, house_price_2025)


gen earnings_growth = ///
    100 * ((earnings_2025 / earnings_2015) - 1) ///
    if !missing(earnings_2015, earnings_2025)


* Positive gap:
* house prices grew faster than earnings.
*
* Negative gap:
* earnings grew faster than house prices.
gen growth_gap = ///
    house_price_growth - earnings_growth ///
    if !missing(house_price_growth, earnings_growth)


label variable house_price_growth ///
    "House-price growth, 2015-2025 (%)"

label variable earnings_growth ///
    "Earnings growth, 2015-2025 (%)"

label variable growth_gap ///
    "House-price growth minus earnings growth (percentage points)"



* ============================================================
* 38. SUMMARISE 2015-2025 GROWTH
* ============================================================

* Use one observation per local authority.
summarize ///
    house_price_growth ///
    earnings_growth ///
    growth_gap ///
    if analysis_authority_tag == 1, ///
    detail


count if analysis_authority_tag == 1 ///
    & !missing(growth_gap)



* ============================================================
* 39. IDENTIFY LARGE GROWTH GAPS
* ============================================================

preserve

keep if analysis_authority_tag == 1

drop if missing(growth_gap)


* Areas where house prices most outpaced earnings.
gsort -growth_gap

display ///
"AREAS WHERE HOUSE PRICES MOST OUTPACED EARNINGS, 2015-2025"

list geography_name ///
     house_price_growth ///
     earnings_growth ///
     growth_gap ///
     in 1/10, ///
     noobs clean


* Areas where earnings performed best relative to prices.
sort growth_gap

display ///
"AREAS WHERE EARNINGS PERFORMED BEST RELATIVE TO HOUSE PRICES, 2015-2025"

list geography_name ///
     house_price_growth ///
     earnings_growth ///
     growth_gap ///
     in 1/10, ///
     noobs clean

restore



* ============================================================
* STEP 7: MEASURE ACTUAL AFFORDABILITY CHANGE
* ============================================================


* ============================================================
* 40. CREATE 2015 AND 2025 AFFORDABILITY VALUES
* ============================================================

bysort geography_code: egen affordability_2015 = ///
    max(cond(year == 2015, affordability_ratio, .))

bysort geography_code: egen affordability_2025 = ///
    max(cond(year == 2025, affordability_ratio, .))



* ============================================================
* 41. CALCULATE AFFORDABILITY CHANGE
* ============================================================

* Ratio-point change.
*
* Positive = less affordable.
* Negative = more affordable.

gen affordability_change = ///
    affordability_2025 - affordability_2015 ///
    if !missing(affordability_2015, affordability_2025)


* Percentage change in the ratio.
gen affordability_pct_change = ///
    100 * ((affordability_2025 / affordability_2015) - 1) ///
    if !missing(affordability_2015, affordability_2025)


label variable affordability_change ///
    "Change in affordability ratio, 2015-2025"

label variable affordability_pct_change ///
    "Percentage change in affordability ratio, 2015-2025"



* ============================================================
* 42. SUMMARISE AFFORDABILITY CHANGE
* ============================================================

summarize ///
    affordability_2015 ///
    affordability_2025 ///
    affordability_change ///
    affordability_pct_change ///
    if analysis_authority_tag == 1, ///
    detail


count if analysis_authority_tag == 1 ///
    & !missing(affordability_change)



* ============================================================
* 43. CLASSIFY THE DIRECTION OF CHANGE
* ============================================================

gen affordability_direction = .

replace affordability_direction = 1 ///
    if affordability_change > 0 ///
    & !missing(affordability_change)

replace affordability_direction = 0 ///
    if affordability_change < 0 ///
    & !missing(affordability_change)

replace affordability_direction = 2 ///
    if affordability_change == 0


label define affordability_direction_lbl ///
    0 "More affordable" ///
    1 "Less affordable" ///
    2 "No change"

label values affordability_direction ///
    affordability_direction_lbl


* Count authorities, not repeated yearly records.
tab affordability_direction ///
    if analysis_authority_tag == 1



* ============================================================
* 44. IDENTIFY THE LARGEST AFFORDABILITY CHANGES
* ============================================================

preserve

keep if analysis_authority_tag == 1

drop if missing(affordability_change)


* Areas where affordability worsened most.
gsort -affordability_change

display ///
"AREAS WHERE HOUSING AFFORDABILITY WORSENED MOST, 2015-2025"

list geography_name ///
     affordability_2015 ///
     affordability_2025 ///
     affordability_change ///
     affordability_pct_change ///
     in 1/10, ///
     noobs clean


* Areas where affordability improved most.
sort affordability_change

display ///
"AREAS WHERE HOUSING AFFORDABILITY IMPROVED MOST, 2015-2025"

list geography_name ///
     affordability_2015 ///
     affordability_2025 ///
     affordability_change ///
     affordability_pct_change ///
     in 1/10, ///
     noobs clean

restore



* ============================================================
* STEP 8: ROBUSTNESS CHECK USING REVISED DATA TO 2024
* ============================================================


* ============================================================
* 45. CREATE 2024 ENDPOINT VALUES
* ============================================================

* 2025 earnings are provisional.
*
* Repeat the endpoint analysis using 2024 so the result can
* be checked using revised earnings data only.

bysort geography_code: egen house_price_2024 = ///
    max(cond(year == 2024, median_house_price, .))

bysort geography_code: egen earnings_2024 = ///
    max(cond(year == 2024, median_annual_pay, .))

bysort geography_code: egen affordability_2024 = ///
    max(cond(year == 2024, affordability_ratio, .))



* ============================================================
* 46. CALCULATE 2015-2024 GROWTH
* ============================================================

gen house_price_growth_2024 = ///
    100 * ((house_price_2024 / house_price_2015) - 1) ///
    if !missing(house_price_2015, house_price_2024)


gen earnings_growth_2024 = ///
    100 * ((earnings_2024 / earnings_2015) - 1) ///
    if !missing(earnings_2015, earnings_2024)


gen growth_gap_2024 = ///
    house_price_growth_2024 - earnings_growth_2024 ///
    if !missing(house_price_growth_2024, earnings_growth_2024)


label variable house_price_growth_2024 ///
    "House-price growth, 2015-2024 (%)"

label variable earnings_growth_2024 ///
    "Earnings growth, 2015-2024 (%)"

label variable growth_gap_2024 ///
    "House-price growth minus earnings growth, 2015-2024"



* ============================================================
* 47. CALCULATE 2015-2024 AFFORDABILITY CHANGE
* ============================================================

gen affordability_change_2024 = ///
    affordability_2024 - affordability_2015 ///
    if !missing(affordability_2015, affordability_2024)


gen affordability_pct_change_2024 = ///
    100 * ((affordability_2024 / affordability_2015) - 1) ///
    if !missing(affordability_2015, affordability_2024)


label variable affordability_change_2024 ///
    "Change in affordability ratio, 2015-2024"

label variable affordability_pct_change_2024 ///
    "Percentage change in affordability ratio, 2015-2024"



* ============================================================
* 48. SUMMARISE THE 2015-2024 ROBUSTNESS RESULTS
* ============================================================

summarize ///
    house_price_growth_2024 ///
    earnings_growth_2024 ///
    growth_gap_2024 ///
    affordability_change_2024 ///
    affordability_pct_change_2024 ///
    if analysis_authority_tag == 1, ///
    detail


count if analysis_authority_tag == 1 ///
    & !missing(affordability_change_2024)



* ============================================================
* 49. CLASSIFY THE 2015-2024 DIRECTION OF CHANGE
* ============================================================

gen affordability_direction_2024 = .

replace affordability_direction_2024 = 1 ///
    if affordability_change_2024 > 0 ///
    & !missing(affordability_change_2024)

replace affordability_direction_2024 = 0 ///
    if affordability_change_2024 < 0 ///
    & !missing(affordability_change_2024)

replace affordability_direction_2024 = 2 ///
    if affordability_change_2024 == 0


* Reuse the labels created for the main analysis.
label values affordability_direction_2024 ///
    affordability_direction_lbl


tab affordability_direction_2024 ///
    if analysis_authority_tag == 1



* ============================================================
* 50. COMPARE MAIN AND ROBUSTNESS RESULTS
* ============================================================

display "2015-2025 MAIN RESULT"

tab affordability_direction ///
    if analysis_authority_tag == 1


display "2015-2024 ROBUSTNESS RESULT"

tab affordability_direction_2024 ///
    if analysis_authority_tag == 1



* ============================================================
* 51. CHECK BOTH RESULTS USING THE SAME AUTHORITIES
* ============================================================

* A clean robustness comparison should use the same
* local authorities in both endpoint analyses.
*
* common_endpoint_sample = 1 only when both:
* - 2015-2025 affordability change is available
* - 2015-2024 affordability change is available

gen common_endpoint_sample = ///
    !missing(affordability_change) ///
    & !missing(affordability_change_2024)


* Number of unique authorities in the common sample.
count if analysis_authority_tag == 1 ///
    & common_endpoint_sample == 1


display "2015-2025: COMMON SAMPLE"

tab affordability_direction ///
    if analysis_authority_tag == 1 ///
    & common_endpoint_sample == 1


display "2015-2024: COMMON SAMPLE"

tab affordability_direction_2024 ///
    if analysis_authority_tag == 1 ///
    & common_endpoint_sample == 1



* ============================================================
* 52. SAVE THE GENERATED FINAL ANALYSIS DATASET
* ============================================================

sort geography_code year

save ///
"$derived/housing_affordability_analysis_2015_2025.dta", ///
replace



* ============================================================
* END ANALYSIS LOG
* ============================================================

log close