# !/usr/bin/env Rscript
# 04/08/2019
#
#' @title FIREcaller: an R package for detecting frequently interacting re-gions from Hi-C data
#'
#' @description This function FIREcaller is a user-friendly R package for detecting FIREs from Hi-C data. 
#' FIREcaller takes raw Hi-C contact matrix as input, performs within-sample and cross-sample normaliza-tion via 
#' HiCNormCis and quantile normalization respectively, and outputs FIRE scores, FIREs and super-FIREs.
#' @usage FIREcaller(prefix.list=(...), gb=c("hg19","GRCh38","mm9","mm10"), map_file="", rm_mhc=c("TRUE","FALSE"))
#' @param prefix.list a list of samples that correspond to the names of the gzipped files.
#' @param gb a string that defines the genome build type.If missing, an error message is returned.
#' @param map_file a string that defines the name of the mappability file specific to the samples genome build, restriction enzyme, and resolution. See read me for format.
#' @param rm_mhc a logical value indicating whether to remove the mhc region of the sample. Default is "TRUE".
#' @details The process includes calculating the raw fire scores, filtering (with the option of removing the MHC region), HiCNormCis, Quantile Normalization (if number of samples > 1), highlighting significant Fire Scores, and calculating the Super Fires.
#' @return Two sets of files will be returned. The total number of files outputted are 1+ (number of prefixes/samples):
#' @return \itemize{
#'     \item Fire: a single text file is outputted for all the samples and all chromosomes.This file contains the Fire Score, associated log10(pvalue), and an indicator if the region is a FIRE or not with I(pvalues > -log(0.05)).
#'     \item SuperFire: a text file for each sample with a list of Super Fires and corresponding -log10(pvalue).
#' }
#' @note Each sample must have a NxN contact frequency matrix for all autosomal chromosomes.
#' The prefix.list corresponds to the naming convention of the NxN contact frequency matrices.
#' If length(prefix.list)>1, quantile normalization is performed.
#' @seealso Paper: https://doi.org/10.1016/j.celrep.2016.10.061
#' @author Crowley, Cheynna Anne <cacrowle@live.unc.edu>, Yuchen Yang <yyuchen@email.unc.edu>,
#' Ming Hu <afhuming@gmail.com>, Yun Li <yunli@med.unc.edu>
#' @references Cheynna Crowley, Yuchen Yang, Ming Hu, Yun Li. FIREcaller: an R package for detecting frequently interacting re-gions from Hi-C data
#' @import MASS
#' @import preprocessCore
#' @import data.table
#' @importFrom stats glm
#' @importFrom stats pnorm
#' @importFrom stats sd
#' @importFrom utils write.table
#' @importFrom utils read.table
#' @examples
#' # set working directory: the location of the NxN matrices and mappability files
#' setwd('~/Documents/Schmitt_Hippo_40KB_input/')
#' 
#' # define the prefix.list according to the naming convention of the NxN matrices
#' prefix.list <- c('Hippo')
#' 
#' #define the genome build
#' gb<-'hg19'
#' 
#' #define the name of the mappability file
#' map_file<-'F_GC_M_HindIII_40KB_hg19.txt.gz'
#' 
#' #define whether to remove MHC region; default=TRUE
#' rm_mhc <- TRUE
#' 
#' #run the function
#' FIREcaller(prefix.list, gb, map_file, rm_mhc)
#' @export
FIREcaller <- function(prefix.list, gb, map_file, rm_mhc){
  options(scipen = 999)

  ref_file <- read.table(map_file, header = TRUE)
  colnames(ref_file) <- c("chr", "start", "end", "F", "GC", "M")
  res <- resolution(ref_file)
  binsize <- bs(ref_file)
  chr_list <- chromosome_list(gb)
  bin_num <- 200000/res

  if(is.null(map_file) == 'TRUE'){stop('Please enter a mappability file')}
  if(length(ref_file) != 6){stop('Please refer to documentation on mappability file format')}
  if(ref_file$start[1] != 0){stop('Please refer to documentation on mappability file format')}
  if(is.null(rm_mhc) == 'TRUE'|| rm_mhc=='TRUE'){rm_mhc<-'TRUE'}
  if(rm_mhc == 'FALSE'){rm_mhc<-'FALSE'}
  if(!rm_mhc %in% c('TRUE','FALSE')){stop('Format for remove mhc is incorrect. Please refer to documentation')}
  if(is.null(chr_list) == 'TRUE'){stop('Format for genome build is incorrect. Please refer to documentation')}

  t <- cis_15KB_200KB(prefix.list, chr_list, bin_num, ref_file)
  t2 <- filter_count(file = t, rm_mhc, bin_num, gb, res)
  t3 <- HiCNormCis(file = t2)
  if(length(prefix.list) > 1){t4 <- quantile_norm(file = t3)}else{t4 <- t3}
  final_fire <- Fire_Call(file = t4, prefix.list, binsize)
  write.table(final_fire, paste0('FIRE_ANALYSIS_', binsize, '.txt'), quote = FALSE, row.names = FALSE)
  Super_Fire(final_fire, res, prefix.list)
}

resolution <- function(ref_file){
  res <- NULL
  map <- ref_file
  res <- (map$end[1] - map$start[1])
  return(res)
}

bs <- function(ref_file){
  binsize <- NULL
  map <- ref_file
  ind <- (map$end[1] - map$start[1])/1000
  if(ind < 100){binsize <- paste0(ind, "KB")}
  if(ind >= 100){
  binsize <- paste0((ind/100), "MB")}
  return(binsize)
}

chromosome_list <- function(gb){
  chr_list <- NULL
  if(toupper(gb) == 'HG19'){chr_list <- paste0('chr', 1:22)}
  if(toupper(gb) == 'GRCH38'){chr_list <- paste0('chr', 1:22)}
  if(toupper(gb) == 'MM9'){chr_list <- paste0('chr', 1:19)}
  if(toupper(gb) == 'MM10'){chr_list <- paste0('chr', 1:19)}
  return(chr_list)
}

cis_15KB_200KB <- function(prefix.list, chr_list, bin_num, ref_file){
  all <- NULL
  for(j in 1:length(chr_list)){
    chr <- chr_list[j]
    x <- cis_single_chr(prefix.list, chr, bin_num, ref_file)
    all <- rbind(all,x)
  }
  return(all)
}

cis_single_chr <- function(prefix.list, chr, bin_num, ref_file){
  file_list <- paste0(prefix.list, '_', chr, '.gz')
  ref_file_chr <- ref_file[ref_file$chr == chr,]
  all_samples <- as.data.frame(ref_file_chr)
  length <- nrow(ref_file_chr)

  for(i in 1:length(file_list)){
    matrix <- fread(file_list[i], data.table = FALSE)
    matrix <- as.matrix(matrix)
    sample <- prefix.list[i]
    diag(matrix) <- 0
    x <- calculate_cis(matrix, chr, bin_num, sample, ref_file_chr, length)
    all_samples <- merge(all_samples, x, by = c("chr", "start", "end", "F", "GC", "M"), sort = FALSE, all = TRUE)
  }

  return(all_samples)
}

calculate_cis <- function(matrix, chr, bin_num, sample, ref_file_chr, length){
  x <- vector("integer", length = length)
  for(i in 1:length){
    x[i] <- ifelse(i <= bin_num, sum(matrix[1:i,i], matrix[i:(i+bin_num),i]),
                 ifelse((i+bin_num) > length, sum(matrix[i:length,i], matrix[(i-bin_num):i,i]), #case 2
                        sum(matrix[(i-bin_num):i, i], matrix[i:(i+bin_num), i]))) #case 3
  }
  x <- as.data.frame(x)
  colnames(x) <- sample
  final <- cbind(ref_file_chr, x)
  return(final)
}

filter_count <- function(file, rm_mhc, bin_num, gb, res){
  y <- file

  # filter 1: remove F=0,GC=0 or M=0
  y_flag <- which(y$F == 0 | y$GC == 0 | y$M == 0)

  # filter 2: remove bad bins of F=0,GC=0 or M=0
  y_bad <- NULL
  for (j in -bin_num:bin_num) {
    y_bad <- c(y_bad, y_flag + j)
  }
  y_bad <- y_bad[y_bad >= 1]
  y_bad <- y_bad[y_bad <= nrow(y)]
  y4 <- y[-unique(y_bad),]

  # filter 3: remove if Mapp<0.9
  y5 <- y4[y4$M > 0.9,]

  #filter 4: MHC regions
  if(rm_mhc == TRUE){
    y6 <- remove_mhc(y5, gb, res)
  } else{
    y6 <- y5
  }
  return(y6)
}

remove_mhc <- function(y, gb, res){
  if(toupper(gb) == 'HG19'){y2 <- mhc_hg19(y, res)}
  if(toupper(gb) == 'GRCH38'){y2 <- mhc_grch38(y, res)}
  if(toupper(gb) == 'MM9'){y2 <- mhc_mm9(y, res)}
  if(toupper(gb) == 'MM10'){y2 <- mhc_mm10(y, res)}
  return(y2)
}

mhc_hg19 <- function(y, res) {
  y_remove <- (y$chr == "chr6" & y$start > floor(28477797/res)*res & y$end <= ceiling(33448354/res)*res)
  y <- y[!y_remove,]
  return(y)
}

mhc_grch38 <- function(y, res) {
  y_remove <- (y$chr == "chr6" & y$start > floor(28510120/res)*res & y$end <= ceiling(33480577/res)*res)
  y <- y[!y_remove,]
  return(y)
}

mhc_mm9 <- function(y, res) {
  y_remove <- (y$chr == "chr17" & y$start > floor(33888191/res)*res & y$end <= ceiling(35744546/res)*res)
  y_remove2 <- (y$chr == "chr17" & y$start > floor(36230820/res)*res & y$end <= ceiling(38050373/res)*res)
  y <- y[!y_remove,]
  y <- y[!y_remove2,]
  return(y)
}

mhc_mm10 <- function(y,res) {
  y_remove <- (y$chr == "chr17" & y$start > floor(33681276/res)*res & y$end <= ceiling(38548659/res)*res)
  y <- y[!y_remove,]
  return(y)
}


HiCNormCis <- function(file){
  x <- file
  corout <- matrix(0, nrow = ncol(x)-6, ncol = 6)
  FIREscore <- x[,1:3]
  for(id in 7:(ncol(x))){
    y <- x[,id]
    fit <- glm(x[,id] ~ x$F + x$GC + x$M, family="poisson")
    summary(fit)
    coeff <- round(fit$coeff, 8)
    res <- round(x[,id]/exp(coeff[1] + coeff[2]*x$F + coeff[3]*x$GC + coeff[4]*x$M), 4)
    FIREscore <- cbind(FIREscore, res)
  }

  FIREscore <- as.data.frame(FIREscore)
  return(FIREscore)
}

quantile_norm <- function(file){
  x <- file
  y <- x[, 4:ncol(x)]
  yqq <- normalize.quantiles(as.matrix(y))
  z <- cbind(x[,1:3], round(yqq,4))
  z <- as.data.frame(z)
  colnames(z) <- colnames(x)
  return(z)
}

Fire_Call <- function(file, prefix.list, binsize){
  x <- file
  alpha <- 0.05
  annp <- x[, 1:3] #fire scores
  annf <- x[, 1:3]
  for(id in 4:ncol(x)){
    y <- x[, id]
    ym  <- mean(y)
    ysd <- sd(y)
    p <- round(-pnorm(y,  mean = ym, sd = ysd, lower.tail = FALSE, log.p = TRUE), 4) #returns log pvalue
    q <- x[ p > -log(alpha),]
    f <- as.numeric(I(p > -log(alpha)))
    annp <- cbind(annp, p)
    annf <- cbind(annf, f)
  }

  annp <- as.data.frame(annp) # log(p-values) scores
  annf <- as.data.frame(annf) #indicators for pvalues > -log(0.05)
  fires <- x

  colnames(annp) <- c('chr', 'start', 'end', paste0(prefix.list, '_logpval'))
  colnames(annf) <- c('chr', 'start', 'end', paste0(prefix.list, '_indicator'))
  colnames(fires) <- c('chr', 'start', 'end', paste0(prefix.list, '_FIRES'))

  final0 <- merge(fires, annp, by = c('chr', 'start', 'end'), all=TRUE, sort = FALSE)
  final <- merge(final0, annf, by = c('chr', 'start', 'end'), all = TRUE, sort = FALSE)
  return(final)
}

Super_Fire <- function(final_fire, res, prefix.list){
  length_pl <- length(prefix.list)
  NP <- final_fire[, c(1:3,(3+1+length_pl):(3+2*length_pl))]
  colnames(NP) <- c('chr', 'start', 'end', prefix.list)
  ID <- final_fire[, c(1:3,(1+3+2*length_pl):ncol(final_fire))]
  colnames(ID) <- c('chr', 'start', 'end', prefix.list)


  for(INDEX in 4:(length_pl+3)){

    x0 <- ID[, c(1:3, INDEX) ]
    y0 <- NP[, c(1:3, INDEX) ]

    x <- x0[x0[,4]==1,]
    z <- y0[x0[,4]==1,]

    final <- NULL
    for(chrid in 1:22){
      u <- z[ z[,1] == paste('chr',chrid,sep=''),]
      out <- NULL
      start <- u[1, 2]
      end <- u[1, 3]
      for(i in 1: (nrow(u)-1) )
      {
        if(abs(end - u[i+1, 2]) <= res)
        {
          end <- u[i+1, 3]
        }
        if(abs(end - u[i+1,2]) > res)
        {
          out <- rbind(out, c(start, end))
          start <- u[i+1, 2]
          end <- u[i+1, 3]
        }
        if(end == u[nrow(u), 3])
        {
          out <- rbind(out, c(start, end))
        }
      }

      SFscore <- rep(0, nrow = nrow(out))
      for(i in 1:nrow(out))
      {
        tmp <- u[u[,2] >= out[i,1] & u[,3] <= out[i,2],]
        SFscore[i] <- sum(tmp[,4])
      }

      sf <- cbind(rep(chrid, nrow(out)), out, SFscore)
      sf <- as.data.frame(sf)
      colnames(sf)<-c('chr', 'start', 'end', 'cum_FIRE_score')

      final <- rbind(final, sf)
    }
    x <- final
    y <- sort(x[,4])
    z <- cbind(seq(1,length(y),1), y)
    z0 <- z

    z[,1] <- z[,1]/max(z[,1])
    z[,2] <- z[,2]/max(z[,2])

    u <- z
    u[,1] <-  1/sqrt(2)*z[,1] + 1/sqrt(2)*z[,2]
    u[,2] <- -1/sqrt(2)*z[,1] + 1/sqrt(2)*z[,2]

    v <- cbind(u, seq(1,nrow(u), 1))
    RefPoint <- v[v[,2] == min(v[, 2]), 3] # 1423
    RefValue <- z0[RefPoint, 2]

    xout <- x[x[,4] >= RefValue,]
    xout$NegLog10Pvalue <- round(xout$cum_FIRE_score/log(10), 4)

    write.table(xout[, c(1:3, 5)], file = paste('super_FIRE_call_', colnames(ID)[INDEX], '.txt', sep=''), row.names = F, col.names = T, sep = '\t', quote = F)
  }
}
