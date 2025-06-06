## -----------------------------------------------------------------------------
##
##' [PROJ: IPEDtaS.R]
##' [FILE: Automagically Download Labelled .dta IPEDS Files]
##' [INIT: March 25th 2024]
##' [UPDT: November 21 2024]
##' [AUTH: Matt Capaldi] @ttalVlatt
##' [CRED: Benjamin T. Skinner] @btskinner
##
## -----------------------------------------------------------------------------

## ---------------------------
##' [README]
## ---------------------------

##' This R script automates downloading IPEDS complete data files and applying
##' labels using the information from IPEDS Stata .do files
##' 
##' To select which files are downloaded, simply add the files you want to the 
##' selected_files list
##' 
##' There is a full tutorial available at https://capaldi.info/IPEDtaS
##' 
##' The resulting files with be a Stata .dta files in the data/ folder
##' 
##' If the required packages readr, haven, dplyr, and stringr are not installed,
##'  the script auto-installs them for you
##' 
##' Note: This does not require Stata or a Stata license, the long loop at the end of
##' the script reads the .do files and applies Haven style labels all within R
##' 
##' This project builds off Dr. Ben Skinner's [`downloadipeds.R` project](https://github.com/btskinner/downloadipeds) and wouldn't have been possible without him or his work


##'----------------------------------------------------------------------------**
##' [Instruction Manual]
##'----------------------------------------------------------------------------**
  
##' 1. Select which files to download (below)
##' 2. Ensure working directory is where you want the files to be stored
##' 3. Hit "Run"

## ---------------------------
##' [File Selection]
## ---------------------------

##' *Edit this list to change the files you download*

##' The only rule is that the `selected_files <- c()` must be a valid list of IPEDS file names
##' Each line/entry **must end in a comma `,`** except the final one

selected_files <- c(
  "HD2023",
  "EFFY2023"
)

# Hint: at the bottom of the script there is a list with every single IPEDS file in it
#       if you want the entire dataset you can just copy and paste that longer list 
#       here and edit as needed
# Hint: "Error ... argument x is empty"
# means you need to delete a comma after your final file

# Hint: "Unexpected string constant"
# means you need to add a comma between those variables

## ---------------------------
##' [Download, Unzip, and Sort Files]
## ---------------------------

needed_packages <- c("readr", "haven", "dplyr", "stringr")

for(i in needed_packages) {
  if(! i %in% installed.packages()) {
    install.packages(i)
  }
}

##'[Create folders if they don't exist]

folders <- c("zip-data", "zip-do-files", "zip-dictionaries",
             "unzip-data", "unzip-do-files", "unzip-dictionaries",
             "data", "dictionaries")

for(i in folders) {
  if(!dir.exists(i)) {
    dir.create(i)
  }
}


##'[Download files from IPEDS if they don't exist]

options(timeout=300)

zip_folders <- c("zip-data", "zip-do-files", "zip-dictionaries")

for(i in selected_files) {
  
  for(j in zip_folders) {
    
    if(!file.exists(paste0("data/", i, ".dta"))) { 
      if(!file.exists(paste0(j, "/", i, ".zip"))) {
        
        extension <- dplyr::case_when(j == "zip-data" ~ "_Data_Stata.zip",
                                      j == "zip-do-files" ~ "_Stata.zip",
                                      j == "zip-dictionaries" ~ "_Dict.zip")
        
        print(paste("Downloading", i, "to", j))
        url <- paste0("https://nces.ed.gov/ipeds/datacenter/data/", i, extension)
        destination <- paste0(j, "/", i, ".zip")
        download.file(url, destination)
        Sys.sleep(3)
        
      }
    }
  }
}


##'[Unzip all downloaded files]

for(i in zip_folders) {
  
  zip_files <- list.files(i, full.names = TRUE)
  
  for(j in zip_files) {
    unzip(j, exdir = paste0("un", i))
    
  }
}


##'[Move any newly downloaded dictionaries over to final dictionary folder]

new_dictionaries <- list.files("unzip-dictionaries")
for(file in new_dictionaries) {
  file.copy(paste0("unzip-dictionaries/", file),
            paste0("dictionaries/", file))
}


##'[Replace revised data with _rv]

rv_data <- list.files("unzip-data",
                      pattern = "_rv|_RV",
                      full.names = TRUE)

for(i in rv_data) {
  
  og_name <- stringr::str_remove(i, "_rv|_RV")
  file.remove(og_name)
  file.rename(i, og_name)
  
}

## ---------------------------
##' [Imitate Stata and use .do files to apply labels]
## ---------------------------


do_files <- list.files("unzip-do-files", full.names = TRUE)

suppressWarnings(
  
  for(i in do_files) {
    
    file_name <- stringr::str_remove_all(i, "unzip-do-files/|\\.do")
    
    if(!file.exists(paste0("data/", file_name, ".dta"))) {
      
      do_file <- readLines(i)
      
      data_file_name <- paste0("unzip-data/", file_name, "_data_stata.csv")
      data_file <- readr::read_csv(data_file_name,
                                   show_col_types = FALSE,
                                   name_repair = "minimal") 
      
      # Remove single instance of duplicated column name by dropping 2nd ef2022a
      data_file <- data_file[!duplicated(colnames(data_file))]
      
      data_file <- data_file |> dplyr::rename_all(stringr::str_to_lower)
      
      variables <- colnames(data_file)
      
      for(var in variables) {
        
        var_values <- c()
        var_value_labels <- c()
        
        for(line in do_file) {
          
          # If it's a variable label
          if(stringr::str_detect(line, paste("^label variable", var))) {
            
            var_label <- stringr::str_extract(line, "\"(.*?)\"")
            var_label <- stringr::str_remove_all(var_label, "\"")
            var_label <- stringr::str_replace_all(var_label, "\\^", "'") # fixes ' showing up as ^
            
          }
          
          # If it's value label
          if(stringr::str_detect(line, paste0("^label define label_", var))) {
            
            value <- stringr::str_split(line, "\\s+")[[1]][4]
            ## If the value is a number, make it numeric
            if(stringr::str_detect(value, "^-?\\d+$")) {
              value <- as.numeric(value)
            }
            
            var_values <- c(var_values, value)
            
            label <- stringr::str_extract(line, "\"(.*?)\"")
            label <- stringr::str_remove_all(label, "\"")
            label <- stringr::str_replace_all(label, "\\^", "'") # fixes ' showing up as ^
            
            var_value_labels <- c(var_value_labels, label)
            
          }
        }
        
        # Work around it reading an entire column of F's as logical (e.g., f1991_f)
        if(is.logical(data_file[[var]])) {
          data_file[[var]] <- stringr::str_trunc(as.character(data_file[[var]]), 1, ellipsis = "")
          # Let us know what vars this happened with
          print(paste("FYI:", file_name,
                      "variable", var, "read as T/F but converted back to string"))
        }
        
        var_value_labels <- setNames(var_values, var_value_labels)
        
        # Don't apply any labels all NA values as it errors
        if(all(is.na(data_file[[var]]))) {
          
          # Let us know what vars this happened with
          print(paste("FYI: No labels applied for", file_name,
                      "variable", var, "due to all NAs"))
          
        } else
          
          if(!is.numeric(var_values)) {
            
            data_file[[var]] <- haven::labelled(data_file[[var]],
                                                label = var_label)
            
            # Let us know what vars this happened with
            #print(paste("FYI: Only applied variable label for", file_name,
             #           "variable", var, "due to string values incompatible with .dta format"))
            
          } else
            
            # Only apply variable labels if there are any duplicate labels as it errors
            
            if(any(duplicated(var_value_labels))) {
              
              data_file[[var]] <- haven::labelled(data_file[[var]],
                                                  label = var_label)
              
              # Also let us know what vars this happened with (not common)
              print(paste("FYI: Only applied variable label for", file_name,
                          "variable", var, "due to duplicate labels in do file"))
              
            } else {
              
              data_file[[var]] <- haven::labelled(data_file[[var]],
                                                  label = var_label,
                                                  labels = var_value_labels)
              
            }
      }
      
      dta_name <- paste0("data/", file_name, ".dta")
      print(paste("Saving", dta_name))
      
      haven::write_dta(data_file, dta_name)
      
    }
  }
)

## ---------------------------
##' [Clean up folders made in the process]
## ---------------------------

unlink("zip-data", recursive = TRUE)
unlink("zip-do-files", recursive = TRUE)
unlink("zip-dictionaries", recursive = TRUE)
unlink("unzip-data", recursive = TRUE)
unlink("unzip-do-files", recursive = TRUE)
unlink("unzip-dictionaries", recursive = TRUE)

## -----------------------------------------------------------------------------
##' *END SCRIPT*
## -----------------------------------------------------------------------------

## ---------------------------
##' [Appendix: Full list of IPEDS files]
## ---------------------------

selected_files <- c("HD2023",
                    "EFFY2023",
                    "F2223_F1A")
#   
#   # 2023
#   
#   "HD2023",
#   "IC2023", 
#   "IC2023_AY", 
#   "IC2023_PY", 
#   "IC2023_CAMPUSES",
#   "FLAGS2023",
#   "EFFY2023",
#   "EFFY2023_DIST", 
#   "EFFY2023_HS", 
#   "EFIA2023", 
#   "ADM2023",
#   "EF2023A",
#   "EF2023B",
#   "EF2023C",
#   "EF2023D",
#   "EF2023A_DIST",
#   "C2023_A", 
#   "C2023_B", 
#   "C2023_C", 
#   "C2023DEP", 
#   "SAL2023_IS",
#   "SAL2023_NIS",
#   "S2023_OC",
#   "S2023_SIS",
#   "S2023_IS",
#   "S2023_NH",
#   "EAP2023",
#   "F2223_F1A",
#   "F2223_F2",
#   "F2223_F3",
#   "SFA2223",
#   "SFAV2223",
#   "GR2023",
#   "GR2023_L2",
#   "GR2023_PELL_SSL",
#   "GR200_23",
#   "OM2023",
#   "AL2023",
#   "DRVIC2023", 
#   "DRVADM2023",
#   "DRVEF2023",
#   "DRVEF122023", 
#   "DRVC2023", 
#   "DRVGR2023",
#   "DRVOM2023",
#   "DRVF2023",
#   "DRVHR2023",
#   "DRVAL2023",
#   
#   # 2022
#   
#   "HD2022",
#   "IC2022",
#   "IC2022_AY",
#   "IC2022_PY",
#   "IC2022_CAMPUSES",
#   "EFFY2022",
#   "EFFY2022_DIST",
#   "EFIA2022",
#   "ADM2022",
#   "EF2022A",
#   "EF2022CP",
#   "EF2022B",
#   "EF2022C",
#   "EF2022D",
#   "EF2022A_DIST",
#   "C2022_A",
#   "C2022_B",
#   "C2022_C",
#   "C2022DEP",
#   "SAL2022_IS",
#   "SAL2022_NIS",
#   "S2022_OC",
#   "S2022_SIS",
#   "S2022_IS",
#   "S2022_NH",
#   "EAP2022",
#   "F2122_F1A",
#   "F2122_F2",
#   "F2122_F3",
#   "SFA2122",
#   "SFAV2122",
#   "GR2022",
#   "GR2022_L2",
#   "GR2022_PELL_SSL",
#   "GR200_22",
#   "OM2022",
#   "AL2022",
#   "FLAGS2022",
#   
#   # 2021
#   
#   "HD2021",
#   "IC2021",
#   "IC2021_AY",
#   "IC2021_PY",
#   "ic2021_campuses",
#   "FLAGS2021",
#   "EFFY2021",
#   "EFFY2021_DIST",
#   "EFIA2021",
#   "ADM2021",
#   "EF2021A",
#   "EF2021B",
#   "EF2021C",
#   "EF2021D",
#   "EF2021A_DIST",
#   "C2021_A",
#   "C2021_B",
#   "C2021_C",
#   "C2021DEP",
#   "SAL2021_IS",
#   "SAL2021_NIS",
#   "S2021_OC",
#   "S2021_SIS",
#   "S2021_IS",
#   "S2021_NH",
#   "EAP2021",
#   "F2021_F1A",
#   "F2021_F2",
#   "F2021_F3",
#   "SFA2021",
#   "SFAV2021",
#   "GR2021",
#   "GR2021_L2",
#   "GR2021_PELL_SSL",
#   "GR200_21",
#   "OM2021",
#   "AL2021",
#   "FLAGS2021",
#   
#   # 2020
#   
#   "HD2020",
#   "IC2020",
#   "IC2020_AY",
#   "IC2020_PY",
#   "EFFY2020",
#   "EFFY2020_DIST",
#   "EFIA2020",
#   "ADM2020",
#   "EF2020A",
#   "EF2020CP",
#   "EF2020B",
#   "EF2020C",
#   "EF2020D",
#   "EF2020A_DIST",
#   "C2020_A",
#   "C2020_B",
#   "C2020_C",
#   "C2020DEP",
#   "SAL2020_IS",
#   "SAL2020_NIS",
#   "S2020_OC",
#   "S2020_SIS",
#   "S2020_IS",
#   "S2020_NH",
#   "EAP2020",
#   "F1920_F1A",
#   "F1920_F2",
#   "F1920_F3",
#   "SFA1920",
#   "SFAV1920",
#   "GR2020",
#   "GR2020_L2",
#   "GR2020_PELL_SSL",
#   "GR200_20",
#   "OM2020",
#   "AL2020",
#   "FLAGS2020",
#   
#   # 2019
#   
#   "HD2019",
#   "IC2019",
#   "IC2019_AY",
#   "IC2019_PY",
#   "EFFY2019",
#   "EFIA2019",
#   "ADM2019",
#   "EF2019A",
#   "EF2019B",
#   "EF2019C",
#   "EF2019D",
#   "EF2019A_DIST",
#   "C2019_A",
#   "C2019_B",
#   "C2019_C",
#   "C2019DEP",
#   "SAL2019_IS",
#   "SAL2019_NIS",
#   "S2019_OC",
#   "S2019_SIS",
#   "S2019_IS",
#   "S2019_NH",
#   "EAP2019",
#   "F1819_F1A",
#   "F1819_F2",
#   "F1819_F3",
#   "SFA1819",
#   "SFAV1819",
#   "GR2019",
#   "GR2019_L2",
#   "GR2019_PELL_SSL",
#   "GR200_19",
#   "OM2019",
#   "AL2019",
#   "FLAGS2019",
#   
#   # 2018
#   
#   "HD2018",
#   "IC2018",
#   "IC2018_AY",
#   "IC2018_PY",
#   "EFFY2018",
#   "EFIA2018",
#   "ADM2018",
#   "EF2018A",
#   "EF2018CP",
#   "EF2018B",
#   "EF2018C",
#   "EF2018D",
#   "EF2018A_DIST",
#   "C2018_A",
#   "C2018_B",
#   "C2018_C",
#   "C2018DEP",
#   "SAL2018_IS",
#   "SAL2018_NIS",
#   "S2018_OC",
#   "S2018_SIS",
#   "S2018_IS",
#   "S2018_NH",
#   "EAP2018",
#   "F1718_F1A",
#   "F1718_F2",
#   "F1718_F3",
#   "SFA1718",
#   "SFAV1718",
#   "GR2018",
#   "GR2018_L2",
#   "GR2018_PELL_SSL",
#   "GR200_18",
#   "OM2018",
#   "AL2018",
#   "FLAGS2018",
#   
#   # 2017
#   
#   "HD2017",
#   "IC2017",
#   "IC2017_AY",
#   "IC2017_PY",
#   "EFFY2017",
#   "EFIA2017",
#   "ADM2017",
#   "EF2017A",
#   "EF2017B",
#   "EF2017C",
#   "EF2017D",
#   "EF2017A_DIST",
#   "C2017_A",
#   "C2017_B",
#   "C2017_C",
#   "C2017DEP",
#   "SAL2017_IS",
#   "SAL2017_NIS",
#   "S2017_OC",
#   "S2017_SIS",
#   "S2017_IS",
#   "S2017_NH",
#   "EAP2017",
#   "F1617_F1A",
#   "F1617_F2",
#   "F1617_F3",
#   "SFA1617",
#   "SFAV1617",
#   "GR2017",
#   "GR2017_L2",
#   "GR2017_PELL_SSL",
#   "GR200_17",
#   "OM2017",
#   "AL2017",
#   "FLAGS2017",
#   
#   # 2016
#   
#   "HD2016",
#   "IC2016",
#   "IC2016_AY",
#   "IC2016_PY",
#   "EFFY2016",
#   "EFIA2016",
#   "ADM2016",
#   "EF2016A",
#   "EF2016CP",
#   "EF2016B",
#   "EF2016C",
#   "EF2016D",
#   "EF2016A_DIST",
#   "C2016_A",
#   "C2016_B",
#   "C2016_C",
#   "C2016DEP",
#   "SAL2016_IS",
#   "SAL2016_NIS",
#   "S2016_OC",
#   "S2016_SIS",
#   "S2016_IS",
#   "S2016_NH",
#   "EAP2016",
#   "F1516_F1A",
#   "F1516_F2",
#   "F1516_F3",
#   "SFA1516",
#   "SFAV1516",
#   "GR2016",
#   "GR2016_L2",
#   "GR2016_PELL_SSL",
#   "GR200_16",
#   "OM2016",
#   "AL2016",
#   "FLAGS2016",
#   
#   # 2015
#   
#   "HD2015",
#   "IC2015",
#   "IC2015_AY",
#   "IC2015_PY",
#   "EFFY2015",
#   "EFIA2015",
#   "ADM2015",
#   "EF2015A",
#   "EF2015B",
#   "EF2015C",
#   "EF2015D",
#   "EF2015A_DIST",
#   "C2015_A",
#   "C2015_B",
#   "C2015_C",
#   "C2015DEP",
#   "SAL2015_IS",
#   "SAL2015_NIS",
#   "S2015_OC",
#   "S2015_SIS",
#   "S2015_IS",
#   "S2015_NH",
#   "EAP2015",
#   "F1415_F1A",
#   "F1415_F2",
#   "F1415_F3",
#   "SFA1415",
#   "SFAV1415",
#   "GR2015",
#   "GR2015_L2",
#   "GR200_15",
#   "OM2015",
#   "AL2015",
#   "FLAGS2015",
#   
#   # 2014
#   
#   "HD2014",
#   "IC2014",
#   "IC2014_AY",
#   "IC2014_PY",
#   "EFFY2014",
#   "EFIA2014",
#   "ADM2014",
#   "EF2014A",
#   "EF2014CP",
#   "EF2014B",
#   "EF2014C",
#   "EF2014D",
#   "EF2014A_DIST",
#   "C2014_A",
#   "C2014_B",
#   "C2014_C",
#   "C2014DEP",
#   "SAL2014_IS",
#   "SAL2014_NIS",
#   "S2014_OC",
#   "S2014_SIS",
#   "S2014_IS",
#   "S2014_NH",
#   "EAP2014",
#   "F1314_F1A",
#   "F1314_F2",
#   "F1314_F3",
#   "SFA1314",
#   "SFAV1314",
#   "GR2014",
#   "GR2014_L2",
#   "GR200_14",
#   "AL2014",
#   "FLAGS2014",
#   
#   # 2013
#   
#   "HD2013",
#   "IC2013",
#   "IC2013_AY",
#   "IC2013_PY",
#   "EFFY2013",
#   "EFIA2013",
#   "IC2013",
#   "EF2013A",
#   "EF2013B",
#   "EF2013C",
#   "EF2013D",
#   "EF2013A_DIST",
#   "C2013_A",
#   "C2013_B",
#   "C2013_C",
#   "C2013DEP",
#   "SAL2013_IS",
#   "SAL2013_NIS",
#   "S2013_OC",
#   "S2013_SIS",
#   "S2013_IS",
#   "S2013_NH",
#   "EAP2013",
#   "F1213_F1A",
#   "F1213_F2",
#   "F1213_F3",
#   "SFA1213",
#   "GR2013",
#   "GR2013_L2",
#   "GR200_13",
#   "FLAGS2013",
#   
#   # 2012
#   
#   "HD2012",
#   "IC2012",
#   "IC2012_AY",
#   "IC2012_PY",
#   "FLAGS2012",
#   "EFFY2012",
#   "EFIA2012",
#   "IC2012",
#   "EF2012A",
#   "EF2012CP",
#   "EF2012B",
#   "EF2012C",
#   "EF2012D",
#   "EF2012A_DIST",
#   "C2012_A",
#   "C2012_B",
#   "C2012_C",
#   "SAL2012_IS",
#   "SAL2012_NIS",
#   "S2012_OC",
#   "S2012_SIS",
#   "S2012_IS",
#   "S2012_NH",
#   "EAP2012",
#   "F1112_F1A",
#   "F1112_F2",
#   "F1112_F3",
#   "SFA1112",
#   "GR2012",
#   "GR2012_L2",
#   "GR200_12",
#   "FLAGS2012",
#   
#   # 2011
#   
#   "HD2011",
#   "IC2011",
#   "IC2011_AY",
#   "IC2011_PY",
#   "EFFY2011",
#   "EFIA2011",
#   "IC2011",
#   "EF2011A",
#   "EF2011B",
#   "EF2011C",
#   "EF2011D",
#   "C2011_A",
#   "SAL2011_A",
#   "SAL2011_Faculty",
#   "SAL2011_A_LT9",
#   "S2011_ABD",
#   "S2011_F",
#   "S2011_G",
#   "S2011_CN",
#   "EAP2011",
#   "F1011_F1A",
#   "F1011_F2",
#   "F1011_F3",
#   "SFA1011",
#   "GR2011",
#   "GR2011_L2",
#   "GR200_11",
#   "FLAGS2011",
#   
#   # 2010
#   
#   "HD2010",
#   "IC2010",
#   "IC2010_AY",
#   "IC2010_PY",
#   "EFFY2010",
#   "EFIA2010",
#   "IC2010",
#   "EF2010A",
#   "EF2010CP",
#   "EF2010B",
#   "EF2010C",
#   "EF2010D",
#   "C2010_A",
#   "SAL2010_A",
#   "SAL2010_B",
#   "SAL2010_FACULTY",
#   "SAL2010_A_LT9",
#   "S2010_ABD",
#   "S2010_F",
#   "S2010_G",
#   "S2010_CN",
#   "EAP2010",
#   "F0910_F1A",
#   "F0910_F2",
#   "F0910_F3",
#   "SFA0910",
#   "GR2010",
#   "GR2010_L2",
#   "GR200_10",
#   "FLAGS2010",
#   
#   # 2009
#   
#   "HD2009",
#   "IC2009",
#   "IC2009_AY",
#   "IC2009_PY",
#   "EFFY2009",
#   "EFIA2009",
#   "IC2009",
#   "EF2009A",
#   "EF2009B",
#   "EF2009C",
#   "EF2009D",
#   "EFEST2009",
#   "C2009_A",
#   "SAL2009_A",
#   "SAL2009_B",
#   "SAL2009_FACULTY",
#   "SAL2009_A_LT9",
#   "S2009_ABD",
#   "S2009_F",
#   "S2009_G",
#   "S2009_CN",
#   "EAP2009",
#   "F0809_F1A",
#   "F0809_F2",
#   "F0809_F3",
#   "SFA0809",
#   "GR2009",
#   "GR2009_L2",
#   "GR200_09",
#   "FLAGS2009",
#   
#   # 2008
#   
#   "HD2008",
#   "IC2008",
#   "IC2008_AY",
#   "IC2008_PY",
#   "EFFY2008",
#   "EFIA2008",
#   "IC2008",
#   "EF2008A",
#   "EF2008CP",
#   "EF2008B",
#   "EF2008C",
#   "EF2008D",
#   "EFEST2008",
#   "C2008_A",
#   "SAL2008_A",
#   "SAL2008_B",
#   "SAL2008_FACULTY",
#   "SAL2008_A_LT9",
#   "S2008_ABD",
#   "S2008_F",
#   "S2008_G",
#   "S2008_CN",
#   "EAP2008",
#   "F0708_F1A",
#   "F0708_F2",
#   "F0708_F3",
#   "SFA0708",
#   "GR2008",
#   "GR2008_L2",
#   "GR200_08",
#   "FLAGS2008",
#   
#   # 2007
#   
#   "HD2007",
#   "IC2007",
#   "IC2007_AY",
#   "IC2007_PY",
#   "IC2007Mission",
#   "EFFY2007",
#   "EFIA2007",
#   "IC2007",
#   "EF2007A",
#   "EF2007B",
#   "EF2007C",
#   "EF2007D",
#   "EFEST2007",
#   "C2007_A",
#   "SAL2007_A",
#   "SAL2007_B",
#   "SAL2007_FACULTY",
#   "SAL2007_A_LT9",
#   "S2007_ABD",
#   "S2007_F",
#   "S2007_G",
#   "S2007_CN",
#   "EAP2007",
#   "F0607_F1A",
#   "F0607_F1A_F",
#   "F0607_F1A_G",
#   "F0607_F2",
#   "F0607_F3",
#   "SFA0607",
#   "GR2007",
#   "GR2007_L2",
#   "FLAGS2007",
#   
#   # 2006
#   
#   "HD2006",
#   "IC2006",
#   "IC2006_AY",
#   "IC2006_PY",
#   "IC2006Mission",
#   "FLAGS2006",
#   "EFFY2006",
#   "EFIA2006",
#   "IC2006",
#   "EF2006A",
#   "EF2006CP",
#   "EF2006B",
#   "EF2006C",
#   "EF2006D",
#   "C2006_A",
#   "SAL2006_A",
#   "SAL2006_B",
#   "SAL2006_FACULTY",
#   "SAL2006_A_LT9",
#   "S2006_ABD",
#   "S2006_F",
#   "S2006_G",
#   "S2006_CN",
#   "EAP2006",
#   "F0506_F1A",
#   "F0506_F1A_F",
#   "F0506_F1A_G",
#   "F0506_F2",
#   "F0506_F3",
#   "SFA0506",
#   "GR2006",
#   "GR2006ATH",
#   "GR2006_ATH_AID",
#   "GR2006_L2",
#   "FLAGS2006",
#   
#   # 2005
#   
#   "HD2005",
#   "IC2005",
#   "IC2005_AY",
#   "IC2005_PY",
#   "IC2005Mission",
#   "EFFY2005",
#   "EFIA2005",
#   "IC2005",
#   "EF2005A",
#   "EF2005B",
#   "EF2005C",
#   "EF2005D",
#   "C2005_A",
#   "SAL2005_A",
#   "SAL2005_B",
#   "SAL2005_A_LT9",
#   "S2005_ABD",
#   "S2005_F",
#   "S2005_G",
#   "S2005_CN",
#   "EAP2005",
#   "F0405_F1A",
#   "F0405_F1A_F",
#   "F0405_F1A_G",
#   "F0405_F2",
#   "F0405_F3",
#   "SFA0405",
#   "GR2005",
#   "GR2005_L2",
#   "GR2005ATH",
#   "GR2005_ATH_AID",
#   "FLAGS2005",
#   "DFR2005",
#   
#   # 2004
#   
#   "HD2004",
#   "FLAGS2004",
#   "IC2004",
#   "IC2004_AY",
#   "IC2004_PY",
#   "IC2004Mission",
#   "EFFY2004",
#   "EFIA2004",
#   "IC2004",
#   "EF2004A",
#   "EF2004CP",
#   "EF2004B",
#   "EF2004C",
#   "EF2004D",
#   "C2004_A",
#   "SAL2004_A",
#   "SAL2004_B",
#   "S2004_ABD",
#   "S2004_F",
#   "S2004_G",
#   "S2004_CN",
#   "EAP2004",
#   "F0304_F1A",
#   "F0304_F1A_F",
#   "F0304_F1A_G",
#   "F0304_F2",
#   "F0304_F3",
#   "SFA0304",
#   "GR2004",
#   "GR2004_L2",
#   "GR2004ATH",
#   "GR2004_ATH_AID",
#   "FLAGS2004",
#   
#   # 2003
#   
#   "HD2003",
#   "IC2003",
#   "IC2003_AY",
#   "IC2003_PY",
#   "EFFY2003",
#   "EFIA2003",
#   "IC2003",
#   "EF2003A",
#   "EF2003B",
#   "EF2003C",
#   "EF2003D",
#   "C2003_A",
#   "SAL2003_A",
#   "SAL2003_B",
#   "S2003_ABD",
#   "S2003_F",
#   "S2003_G",
#   "S2003_CN",
#   "EAP2003",
#   "F0203_F1",
#   "F0203_F1A",
#   "F0203_F1A_F",
#   "F0203_F1A_G",
#   "F0203_F2",
#   "F0203_F3",
#   "SFA0203",
#   "GR2003",
#   "GR2003ATH",
#   "GR2003_ATH_AID",
#   
#   # 2002
#   
#   "HD2002",
#   "IC2002",
#   "IC2002_AY",
#   "IC2002_PY",
#   "EFFY2002",
#   "EFIA2002",
#   "IC2002",
#   "EF2002A",
#   "EF2002CP",
#   "EF2002B",
#   "EF2002C",
#   "EF2002D",
#   "C2002_A",
#   "SAL2002_A",
#   "SAL2002_B",
#   "S2002_ABD",
#   "S2002_F",
#   "S2002_G",
#   "S2002_CN",
#   "EAP2002",
#   "F0102_F1",
#   "F0102_F1A",
#   "F0102_F1A_F",
#   "F0102_F1A_G",
#   "F0102_F2",
#   "F0102_F3",
#   "SFA0102",
#   "GR2002",
#   "GR2002ATH",
#   "GR2002_ATH_AID",
#   
#   # 2001
#   
#   "FA2001HD",
#   "IC2001",
#   "IC2001_AY",
#   "IC2001_PY",
#   "EF2001D1",
#   "EF2001D2",
#   "IC2001",
#   "EF2001A",
#   "EF2001B",
#   "EF2001C",
#   "EF2001E",
#   "C2001_A",
#   "c2001_a2dig",
#   "SAL2001_A_S",
#   "SAL2001_B_S",
#   "S2001_ABD",
#   "S2001_F",
#   "S2001_G",
#   "S2001_CN",
#   "EAP2001",
#   "F0001_F1",
#   "F0001_F2",
#   "F0001_F3",
#   "SFA0001S",
#   "GR2001",
#   "GR2001_L2",
#   "GR2001ATH",
#   "GR2001_ATH_AID",
#   
#   # 2000
#   
#   "FA2000HD",
#   "IC2000",
#   "IC2000_ACTOT",
#   "IC2000_AY",
#   "IC2000_PY",
#   "EF2000D",
#   "EF2000A",
#   "EF2000CP",
#   "EF2000B",
#   "EF2000C",
#   "C2000_A",
#   "C2000_A2DIG",
#   "F9900_F1",
#   "F9900F2",
#   "F9900F3",
#   "SFA9900S",
#   "GR2000",
#   "GR2000_L2",
#   "GR2000ATH",
#   "GR2000_ATH_AID",
#   
#   # 1999
#   
#   "IC99_HD",
#   "IC99ABCF",
#   "IP1999AY",
#   "IP1999PY",
#   "IC99_ACTOT",
#   "IC99_D",
#   "IC99_E",
#   "EF99_ANR",
#   "EF99_B",
#   "EF99_D",
#   "C9899_A",
#   "C9899_B",
#   "SAL1999_A",
#   "SAL1999_B",
#   "S1999_ABD",
#   "S1999_F",
#   "S1999_G",
#   "S99_CN",
#   "S99_E",
#   "F9899_F1",
#   "F9899_C5",
#   "F9899_F2",
#   "F9899_F3",
#   "F9899_CN",
#   "Pub_studentCount",
#   "Pub_FinancialAid",
#   "GR1999",
#   "GR1999_L2",
#   "GR1999ATH",
#   "GR1999_ATH_AID",
#   
#   # 1998
#   
#   "IC98hdac",
#   "IC98_AB",
#   "IC98_C",
#   "IC98_D",
#   "IC98_F",
#   "IC98_E",
#   "EF98_hd",
#   "EF98_ANR",
#   "EF98_ARK",
#   "EF98_ACP",
#   "EF98_C",
#   "EF98_D",
#   "C9798_HD",
#   "C9798_A",
#   "C9798_A2DIG",
#   "C9798_B",
#   "SAL98_HD",
#   "SAL98_A",
#   "SAL98_B",
#   "F9798_F1",
#   "F9798_C5",
#   "F9798_F2",
#   "F9798_F3",
#   "F9798_CN",
#   "GR1998",
#   "GR1998_L2",
#   "GR1998ATH",
#   "GR1998_ATH_AID",
#   "ic9798_HDR",
#   "ic9798_AB",
#   "ic9798_C",
#   "ic9798_D",
#   "ic9798_F",
#   "ic9798_E",
#   
#   # 1997
#   
#   "EF97_HDR",
#   "EF97_ANR",
#   "EF97_ARK",
#   "EF97_B",
#   "EF97_D",
#   "C9697_HDR",
#   "C9697_A",
#   "C9697_A2DIG",
#   "C9697_B",
#   "SAL97_HDR",
#   "SAL97_A",
#   "SAL97_B",
#   "S97_IC",
#   "S97_S",
#   "S97_E",
#   "S97_CN",
#   "F9697_F1",
#   "F9697_F2",
#   "GR1997",
#   "GR1997_L2",
#   "GR1997ATH",
#   "GR1997_ATH_AID",
#   "ic9697_A",
#   "ic9697_B",
#   "ic9697_C",
#   
#   # 1996
#   
#   "EF96_IC",
#   "EF96_ANR",
#   "EF96_ACP",
#   "EF96_ARK",
#   "EF96_C",
#   "EF96_D",
#   "C9596_IC",
#   "C9596_A",
#   "C9596_A2DIG",
#   "C9596_B",
#   "SAL96_IC",
#   "SAL96_a_1",
#   "SAL96_B",
#   "F9596_IC",
#   "F9596_A",
#   "F9596_B",
#   "F9596_C",
#   "F9596_C5",
#   "F9596_D",
#   "F9596_E",
#   "F9596_F",
#   "F9596_G",
#   "F9596_H",
#   "F9596_I",
#   "F9596_J",
#   "F9596_K",
#   "F9596_CN",
#   "ic9596_A",
#   "ic9596_B",
#   
#   # 1995
#   
#   "EF95_IC",
#   "EF95_ANR",
#   "EF95_ARK",
#   "EF95_B",
#   "EF95_D",
#   "C9495_IC",
#   "C9495_A",
#   "C9495_A2DIG",
#   "C9495_B",
#   "SAL95_IC",
#   "SAL95_a_1",
#   "SAL95_B",
#   "s95_ic",
#   "S95_S",
#   "s95_e",
#   "S95_CN",
#   "F9495_IC",
#   "F9495_A",
#   "F9495_B",
#   "F9495_C",
#   "F9495_C5",
#   "F9495_D",
#   "F9495_E",
#   "F9495_F",
#   "F9495_G",
#   "F9495_H",
#   "F9495_I",
#   "F9495_J",
#   "F9495_K",
#   
#   # 1994
#   
#   "IC1994_A",
#   "IC1994_B",
#   "EF1994_IC",
#   "EF1994_ANR",
#   "EF1994_ACP",
#   "EF1994_ARK",
#   "EF1994_C",
#   "EF1994_D",
#   "C1994_IC",
#   "C1994_CIP",
#   "C1994_RE",
#   "SAL1994_A",
#   "SAL1994_B",
#   "F1994_IC",
#   "F1994_A",
#   "F1994_B",
#   "F1994_C",
#   "F1994_D",
#   "F1994_E",
#   "F1994_F",
#   "F1994_G",
#   "F1994_H",
#   "F1994_I",
#   "F1994_J",
#   "F1994_K",
#   
#   # 1993
#   
#   "IC1993_A",
#   "IC1993_B",
#   "EF1993_IC",
#   "EF1993_A",
#   "EF1993_B",
#   "EF1993_D",
#   "C1993_IC",
#   "C1993_CIP",
#   "C1993_RE",
#   "SAL1993_A",
#   "SAL1993_B",
#   "S1993_IC",
#   "S1993_ABCEF",
#   "S1993_CN",
#   "F1993_IC",
#   "F1993_A",
#   "F1993_B",
#   "F1993_C",
#   "F1993_D",
#   "F1993_E",
#   "F1993_F",
#   "F1993_G",
#   "F1993_H",
#   "F1993_I",
#   "F1993_J",
#   "F1993_K",
#   
#   # 1992
#   
#   "IC1992_A",
#   "IC1992_B",
#   "EF1992_IC",
#   "EF1992_A",
#   "EF1992_C",
#   "C1992_IC",
#   "C1992_CIP",
#   "C1992_RE",
#   "SAL1992_A",
#   "SAL1992_B",
#   "F1992_IC",
#   "F1992_A",
#   "F1992_B",
#   "F1992_C",
#   "F1992_D",
#   "F1992_E",
#   "F1992_F",
#   "F1992_G",
#   "F1992_H",
#   "F1992_I",
#   "F1992_J",
#   "F1992_K",
#   
#   # 1991
#   
#   "ic1991_ab",
#   "ic1991_c",
#   "ic1991_d",
#   "ic1991_e",
#   "ic1991_f",
#   "IC1991_hdr",
#   "ic1991_other",
#   "ef1991_hdr",
#   "ef1991_a",
#   "ef1991_b",
#   "C1991_HDR",
#   "c1991_cip",
#   "c1991_re",
#   "sal1991_a",
#   "sal1991_b",
#   "sal1991_hdr",
#   "s1991_a",
#   "s1991_b",
#   "s1991_hdr",
#   "F1991_hdr",
#   "F1991_A",
#   "F1991_B",
#   "F1991_C",
#   "F1991_D",
#   "F1991_E",
#   "F1991_F",
#   "F1991_G",
#   "F1991_H",
#   "F1991_I",
#   "F1991_J",
#   "F1991_K",
#   
#   # 1990
#   
#   "IC90HD",
#   "IC90ABCE",
#   "IC90D",
#   "EF90_HD",
#   "EF90_A",
#   "C8990HD",
#   "C8990RE",
#   "C8990CIP",
#   "SAL90_HD",
#   "SAL90_A",
#   "SAL90_B",
#   "F8990_HD",
#   "F8990_A",
#   "F8990_B",
#   "F8990_E",
#   
#   # 1989
#   
#   "IC1989_A",
#   "IC1989_B",
#   "EF1989_IC",
#   "EF1989_A",
#   "C1989_IC",
#   "C1989_CIP",
#   "C1989_RE",
#   "SAL1989_IC",
#   "SAL1989_A",
#   "SAL1989_B",
#   "S1989_IC",
#   "S1989",
#   "F1989_IC",
#   "F1989_A",
#   "F1989_B",
#   "F1989_C",
#   "F1989_D",
#   "F1989_E",
#   "F1989_F",
#   "F1989_G",
#   "F1989_H",
#   "F1989_I",
#   "F1989_J",
#   "F1989_K",
#   
#   # 1988
#   
#   "IC1988_A",
#   "IC1988_B",
#   "EF1988_IC",
#   "EF1988_A",
#   "RES1988_IC",
#   "EF1988_C",
#   "C1988_IC",
#   "C1988_CIP",
#   "C1988_A2DIG",
#   "F1988",
#   
#   # 1987
#   
#   "IC1987_A",
#   "IC1987_B",
#   "EF1987_IC",
#   "EF1987_A",
#   "EF1987_B",
#   "EF1987_D",
#   "C1987_IC",
#   "C1987_CIP",
#   "C1987_RE",
#   "SAL1987_IC",
#   "SAL1987_A",
#   "SAL1987_B",
#   "S1987_IC",
#   "S1987",
#   "F1987_A",
#   "F1987_B",
#   "F1987_E",
#   "F1987_IC",
#   
#   # 1986
#   
#   "IC1986_A",
#   "IC1986_B",
#   "EF1986_IC",
#   "EF1986_A",
#   "EF1986_ACP",
#   "EF1986_D",
#   "RES1986_IC",
#   "EF1986_C",
#   "C1986_CIP",
#   "C1986_A2dig",
#   "F1986",
#   
#   # 1985
#   
#   "IC1985",
#   "EF1985",
#   "C1985_CIP",
#   "C1985_RE",
#   "C1985_IC",
#   "SAL1985_IC",
#   "SAL1985_A",
#   "SAL1985_B",
#   "F1985",
#   
#   # 1984
#   
#   "IC1984",
#   "EF1984",
#   "C1984_CIP",
#   "C1984_A2dig",
#   "SAL1984_IC",
#   "SAL1984_A",
#   "SAL1984_B",
#   "F1984",
#   
#   # 1980
#   
#   "IC1980",
#   "EF1980_A",
#   "EF1980_ACP",
#   "C1980SUBBA_CIP",
#   "C1980SUBBA_2DIG",
#   "C1980_4ORMORE_CIP",
#   "C1980_4ORMORE_2DIG",
#   "SAL1980_A",
#   "SAL1980_B",
#   "F1980"
#   
# ) # Hint: do not comment this bracket out!
