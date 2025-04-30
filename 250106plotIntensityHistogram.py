#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Mon Nov  9 15:12:47 2020

@author: yaginumanojilab
"""

#241216版の修正で達成したいこと：ROG基準で除外した点のみでヒストグラムを書く、あるいは薄い色でヒストグラムに表示できるようにする。

#%%

import pandas as pd
import numpy as np
import scipy
import seaborn as sns
import matplotlib.pyplot as plt
import os
import re
import csv
import glob

from time import strftime, localtime


#%%
filepath =  "/Users/suzukiryoko/Desktop/240201/100uM_NTPs/240201_CYTOP-TwistAmp_Mix_2-98_100uM-NTPs_4pM_SCoV2SP8_30min-q10486601_001c1_008_2_3_2501061232_WTH(50).csv"
#210617_CYTOP-145RN-0_1pMbGal-q10202001_001c1t002_001_2_4_2110121805_WTH.csv
#210617_CYTOP-145RN-0_1pMbGal-q10202001_001c1t001_001_2_4_2110121846_WTH.csv
multiple_files = False
data_is_timelapse = False #True if data is timelapse
plot_frame = 3 # starts from 1. 1 (t001), 2 (t002), ... #If data_is_timelapse = False, plot_frame is ignored
xlabel = "Intensity" # histogram x label
ylabel = "Counts" #histogram y label

#Histogram parameters
binnum = 1100 #125 bins
histomin, histomax = -500, 5000 #histogram from -5 to 20, usally no need to change
plotxmin, plotxmax = -50, 500 #range to plot in figure. 
countmin1, countmax1 = 0, 100 #histogram figure vertical axis (count) limits (full view)
setcountmax_auto = False #If true, countmax1 will be ignored and limit of vertical axis is set automatically.

#Gaussian fitting parameters
initGuess = [1600,40,10] # initial paramter (A, mu, sigma) of gaussian fit
threshold_sd_margin = 15 #5-15

#Manual Threshold setting
manual_thresholding = False # if True, Gaussian fitting is skipped.
manual_threshold = 1000

#Analysis of ROG
rogdata_exist = True
rog_threshold = 5.5
plot_rog_excluded_points = -1 #Whether to plot points excluded by ROG critria in the histogram. 0: No, 1: Yes, -1: Plot using light colors.

#resolution of result image by dot-per-inch
result_dpi = 300
plot_mode = 1 # mode 0: standard figure & text outside, mode 1: wide figure & text inside, 2: standard figure & half plotxmin and plotxmax & text outside 3: y-axis compressed histogram & text outside



#%%

#Combine multiple files
multiple_files = True
data_is_timelapse = False #タイムラプスの場合の複数ファイル読み込み結合は未対応

multi_filepath_dir = "/Users/suzukiryoko/Desktop/240201/100uM_NTPs/"

#複数ファイルの選定
pathlist = glob.glob(multi_filepath_dir + "*")
r = re.compile(".*\.csv")
pathlist_peakint = list(filter(r.match, pathlist))
filename_peakint_list = [os.path.split(x)[-1] for x in pathlist_peakint]
filename_peakint_list.sort()
for i in range(len(filename_peakint_list)):
    print(str(i) + " " + filename_peakint_list[i]  )

val = input('Enter numbers of peak intensity result file to plot (separate by spaces): ')

print('Your value: ', val)

newname = input('Enter new base file name for the concatenated results: ')
print('Your value: ', newname)

#データの結合

peakint_df_numbers = [int(x) for x in re.split(" ", val)]
peakint_df_list = [0 for x in range(len(peakint_df_numbers))]
for k in range(len(peakint_df_numbers)):
    peakint_df_list[k] = pd.read_csv(multi_filepath_dir + filename_peakint_list[peakint_df_numbers[k]], delimiter = ",", header = None, encoding = "ISO-8859-1")
    cols = len(peakint_df_list[k].columns)
    rows = len(peakint_df_list[k])
    peakint_df_list[k][cols] = [filename_peakint_list[peakint_df_numbers[k]]] * rows
    
peakint_df = pd.concat(peakint_df_list)

#%%

#ROG情報のあるデータというクラスを作成して呼び出しやすくする
class DataWithRog:
    def __init__(self, input_df, rog_threshold):
        self.input_data = input_df
        self.rog_threshold = rog_threshold
        self.rog_pos_data = input_df[input_df["ROG"] < rog_threshold]
        self.rog_pos_length = len(self.rog_pos_data)
    
    def set_histo_colors(self, plot_rog_excluded_points):
        self.plot_rog_excluded_points = plot_rog_excluded_points
        if(plot_rog_excluded_points==-1):
            self.histocolors = ('#c1cbe7', '#4169e1')
            self.show_omitted_dexcription = "ROG-excluded points shown in light colors."
        elif(plot_rog_excluded_points==1):
            self.histocolors = ('#4169e1', '#4169e100')
            self.show_omitted_dexcription = "ROG-excluded points are shown in histogram (not excluded)."
        elif(plot_rog_excluded_points==0):
            self.histocolors = ( '#4169e100', '#4169e1')
            self.show_omitted_dexcription = "ROG-excluded points are omitted from histogram."
        else:
            print("plot_rog_excluded_pointsの値は0, 1, -1のどれかである必要があります。処理を中止します。")
            exit()    
            
    def set_histo_description(self, intensity_threshold, manual_thresholding=False, threshold_sd_margin=-1):
        self.y_rog_positive = list(filter(lambda x: x>intensity_threshold, self.rog_pos_data["PeakIntensity"]))
        if(manual_thresholding):
            int_thres_description =  "> man. thres. (>" +  "{:.1f}".format(intensity_threshold) +") "
        else:
             int_thres_description =  ">" + "{:d}".format(threshold_sd_margin) + "SD (>" +  "{:.1f}".format(intensity_threshold) +") "
        rog_thres_description = "ROG < " + "{:.1f}".format(self.rog_threshold) + " "
        self.histo_description = self.show_omitted_dexcription + "\n" + int_thres_description + "& " + rog_thres_description +  ": " + "{:d}".format(len(self.y_rog_positive)) + "/" + "{:d}".format(len(self.input_data))    
        
#必要なデータの読み込み
if(multiple_files):
    if(data_is_timelapse):
        print("複数ファイル＆タイムラプスの処理は未対応です。処理を中止します。")
        exit()
    else:
        data = peakint_df[0]
        if(rogdata_exist):
            df2 = pd.DataFrame({"PeakIntensity": peakint_df[0],  "ROG": peakint_df[3], "X": peakint_df[1],  "Y": peakint_df[2], "exp": peakint_df[4]})
        else:
            df2 = pd.DataFrame({"PeakIntensity": peakint_df[0],   "X": peakint_df[1],  "Y": peakint_df[2], "exp": peakint_df[cols]})
        df2wR = DataWithRog(df2, rog_threshold)
        
else:
    df1 = pd.read_csv(filepath, delimiter = ",", header = None, encoding = "ISO-8859-1")
    df1array = np.array(df1)
    if(data_is_timelapse):
        peakIntensity_array = df1array[plot_frame-1, :]
    else:
        peakIntensity_array = df1array[:, 0]
    data = list(peakIntensity_array)

    if(rogdata_exist):
        if(data_is_timelapse):
            df1r = pd.read_csv(filepath.replace( ".csv", "_ROG.csv"), delimiter = ",", header = None, encoding = "ISO-8859-1")
            df1r_array = np.array(df1r)
            rog_array = df1r_array[plot_frame-1, :]
            data_rog = list(rog_array)
            df2 = pd.DataFrame({"PeakIntensity": data,  "ROG": data_rog})
        else:
            df2 = pd.DataFrame({"PeakIntensity": data,  "ROG": df1array[:, 3], "X": df1array[:, 1],  "Y": df1array[:, 2]})
        df2wR = DataWithRog(df2, rog_threshold)


#タイトルの文字
if(multiple_files):
    shorttitle = newname
else:
    shorttitle = filepath.split("/")[-1]
    shorttitle = shorttitle.replace(".csv", "")
    #shorttitle = re.sub( "_[0-9]+c1t[0-9]+", "",shorttitle) #210830 視野が001以外の時に001になってしまうのが困るのでここの行をコメントアウトして消しました。
    shorttitle = re.sub( "_[0-9]{10}", "",shorttitle) #remove unimportant part from file names and use it as shorttitle.
    if(data_is_timelapse):
        shorttitle = re.sub("t[0-9]{3}", "t" + "{:03d}".format(plot_frame), shorttitle)
    
print(shorttitle)

#ヒストグラム作成
bins = np.linspace(histomin, histomax, binnum + 1)
thisHistoCount = np.histogram(data, bins)[0]
thisHistoFrac = np.array([x/len(data) for x in thisHistoCount])

headerBase = shorttitle + "-Histodata" 
histoHeader = ["bins Intensity", headerBase + " Count", headerBase + " Frac"]

if(plot_mode == 2):
    fig_width = 7.5
    fig_height = 5
    text_pos_x = 2
    text_pos_y = 0.98
    plotxmax_adjuster = 2
elif(plot_mode == 1): 
    fig_width = 15
    fig_height = 5
    text_pos_x = 0.98
    text_pos_y = 0.98
    plotxmax_adjuster = 1
elif(plot_mode == 3): 
    fig_width = 5
    fig_height = 1
    text_pos_x = 0.98
    text_pos_y = 5
    plotxmax_adjuster = 1
else:
    fig_width = 7.5
    fig_height = 5
    text_pos_x = 2
    text_pos_y = 0.98
    plotxmax_adjuster = 1
    

fig = plt.figure(figsize=(fig_width, fig_height))
plt.rcParams["font.size"] = 16
ax = fig.add_subplot(1,1,1)
plt.subplots_adjust(hspace = 0.3)


edges = np.zeros(binnum+1)
for i in range(binnum+1):
    edges[i] = histomin + (histomax - histomin) / binnum * i
if(rogdata_exist):
    df2wR.set_histo_colors(plot_rog_excluded_points)
    n, bins, patches = ax.hist(data, bins=edges, rwidth = 0.7, color=df2wR.histocolors[0])
    n_rogpositive, _, _ = ax.hist(df2wR.rog_pos_data["PeakIntensity"], bins=edges, rwidth = 0.7, color=df2wR.histocolors[1])
else:
    n, bins, patches = ax.hist(data, bins=edges, rwidth = 0.7, color="tab:blue")
    
ax.set_title('Histogram of \n' + shorttitle, fontsize = 12, pad=15)
ax.set_xlabel(xlabel)
ax.set_ylabel(ylabel)
ax.set_xlim(plotxmin / plotxmax_adjuster, plotxmax / plotxmax_adjuster)
ax.set_ylim(countmin1, countmax1)
maxfreq = n.max()
if setcountmax_auto:
    plt.ylim(ymax=np.ceil(maxfreq / 10) * 10 if maxfreq % 10 else maxfreq + 10)

#ガウシアンフィッティング
if(manual_thresholding):
    threshold = manual_threshold
    ypositive = list(filter(lambda x: x>threshold, data))
    plt.axvline(x = threshold, linestyle = "dotted", color = 'red')

else:
    binwidth = (histomax - histomin)/binnum
    x = np.linspace(histomin + binwidth/2, histomax - binwidth/2, binnum)
    y = n
    
    def Gaussian(x,a,b,c):
        return a * np.exp(-(x - b)**2.0 / (2 * c**2))
    def Gaussian_zero(x,a,c):
        return a * np.exp(-x**2.0 / (2 * c**2))
    
    
    popt, pcov = scipy.optimize.curve_fit(Gaussian, x, y, p0=initGuess)
    curve = Gaussian(x, popt[0], popt[1], popt[2])
    plt.plot(x, curve, color="tab:orange")
    
    threshold = popt[1] + threshold_sd_margin * np.abs(popt[2])
    ypositive = list(filter(lambda x: x>threshold, data))
    plt.axvline(x = threshold, linestyle = "dotted", color = 'red')

if(rogdata_exist):
    df2positive_int = df2[df2["PeakIntensity"] > threshold]
    df2positive_introg = df2positive_int[df2positive_int["ROG"] < rog_threshold]
    

#右上のテキスト
if(manual_thresholding):
    gaussfittext = "Manual threshold : " + "{:.1f}".format(manual_threshold)
    npositivetext = "> man. thres.: " + "{:d}".format(len(ypositive)) + "/" + "{:d}".format(len(data))
    if(rogdata_exist):
        df2wR.set_histo_description(manual_threshold, manual_thresholding=True)
        npositivetext = npositivetext + "\n" + df2wR.histo_description
else:
    gaussfittext = "Fit (mu,sigma) = (" + "{:.1f}".format(popt[1]) + ", " + "{:.1f}".format(popt[2]) + ")"
    npositivetext = ">" + "{:d}".format(threshold_sd_margin) + "SD (>" + "{:.1f}".format(threshold) +") : " + "{:d}".format(len(ypositive)) + "/" + "{:d}".format(len(data))
    if(rogdata_exist):
        df2wR.set_histo_description(threshold, threshold_sd_margin=threshold_sd_margin)
        npositivetext = npositivetext + "\n" + df2wR.histo_description


outrangesum = len(list(filter(lambda x: x > plotxmax, data))) + len(list(filter(lambda x: x < plotxmin, data)))
outrangetext = "{:d}".format(outrangesum) + " data points out of range"
info_text = "\n".join([outrangetext, gaussfittext, npositivetext])
plt.text(text_pos_x, text_pos_y, info_text, horizontalalignment='right', verticalalignment='top', transform=ax.transAxes)

#使用したcsvのファイル名（複数ファイル結合時）
if(multiple_files):
    peakint_filenames_text = "\n".join([filename_peakint_list[k] for k in peakint_df_numbers])
    plt.text(0, -0.20, peakint_filenames_text, horizontalalignment='left', verticalalignment='top', transform=ax.transAxes)

#画像保存
if(multiple_files):
    filepath_dir = multi_filepath_dir
else:
    filepath_dir  = "/".join(filepath.split("/")[0:-1] + [""] )
plt.savefig(filepath_dir + shorttitle +  "_PeakHis_" + strftime("%y%m%d%H%M", localtime()) + '.png', bbox_inches='tight', pad_inches=0.5, dpi=result_dpi)

#parameter export 
list_paraexport = [["filepath",  filepath]]
list_paraexport = list_paraexport + [["binnum", "{:d}".format(binnum)], ["histomin", "{:d}".format(histomin)], ["histomax", "{:d}".format(histomax)] ]
list_paraexport = list_paraexport + [["plotxmin", "{:d}".format(plotxmin)], ["plotxmax", "{:d}".format(plotxmax)] ]
list_paraexport = list_paraexport + [["countmin", "{:d}".format(countmin1)], ["countmax", "{:d}".format(countmax1)], ["setcountmax_auto", str(setcountmax_auto)] ]
list_paraexport = list_paraexport + [["initGuess", ",".join(["{:.3f}".format(x) for x in initGuess])]]  
list_paraexport = list_paraexport + [["threshold_sd_margin", "{:d}".format(threshold_sd_margin)]]
 

filepath_dir = "/".join(filepath.split("/")[0:-1] + [""] )
title_paraexport = shorttitle +  "_parameters_" + strftime("%y%m%d%H%M", localtime()) + '.txt'   
with open(filepath_dir + title_paraexport, "w") as output:
    writer = csv.writer(output, lineterminator='\n')
    writer.writerows(list_paraexport)


#%%
from matplotlib import gridspec

if(plot_mode == 2):
    fig_width = 15
    text_pos_x = 0.98
    plotxmax_adjuster = 2
    width_r = (2,1)
elif(plot_mode == 1): 
    fig_width = 15
    text_pos_x = 0.98
    plotxmax_adjuster = 1
    width_r = (2,1)
else:
    fig_width = 15
    text_pos_x = 0.98
    plotxmax_adjuster = 1
    width_r = (2,1)

if(rogdata_exist):
    #ヒストグラム再描画
    fig = plt.figure(figsize=(fig_width, 5))
    plt.rcParams["font.size"] = 16
    spec = gridspec.GridSpec(ncols=2, nrows=1,
                             width_ratios=width_r)
    ax = fig.add_subplot(spec[0])
    plt.subplots_adjust(hspace = 0.3)
    n, bins, patches = ax.hist(data, bins=edges, rwidth = 0.7, color=df2wR.histocolors[0])
    n_rogpositive, _, _ = ax.hist(df2wR.rog_pos_data["PeakIntensity"], bins=edges, rwidth = 0.7, color=df2wR.histocolors[1])
    n_rogintpositive, _, _ = ax.hist(df2positive_introg["PeakIntensity"], bins=edges, rwidth = 0.7, color='#ae435a')
    ax.set_title('Histogram of \n' + shorttitle, fontsize = 12, pad=15)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.set_xlim(plotxmin / plotxmax_adjuster, plotxmax / plotxmax_adjuster)
    ax.set_ylim(countmin1, countmax1)
    maxfreq = n.max()
    if setcountmax_auto:
        plt.ylim(ymax=np.ceil(maxfreq / 10) * 10 if maxfreq % 10 else maxfreq + 10)

    if(manual_thresholding):
        threshold = manual_threshold
        plt.axvline(x = threshold, linestyle = "dotted", color = 'red')
    
    else:
        popt, pcov = scipy.optimize.curve_fit(Gaussian, x, y, p0=initGuess)
        curve = Gaussian(x, popt[0], popt[1], popt[2])
        plt.plot(x, curve, color="tab:orange")
        threshold = popt[1] + threshold_sd_margin * np.abs(popt[2])
        ypositive = list(filter(lambda x: x>threshold, data))
        plt.axvline(x = threshold, linestyle = "dotted", color = 'red')

    df2positive_int = df2[df2["PeakIntensity"] > threshold]
    df2positive_introg = df2positive_int[df2positive_int["ROG"] < rog_threshold]
    df2negative_int = df2[df2["PeakIntensity"] <= threshold]

#以下は一時期検討していた別のfittingの方法だが、使わないのでコメントアウトした。
#    popt2, pcov2 = scipy.optimize.curve_fit(Gaussian_zero, x, y, p0=[initGuess[0], initGuess[2]] )
#    curve2 = Gaussian_zero(x, popt2[0], popt2[1])
#    plt.plot(x, curve2) 
#    print(popt2[1]*15)
#    threshold2 = 0 + threshold_sd_margin * np.abs(popt2[1])
#    ypositive2 = list(filter(lambda x: x>threshold2, data))
#    gaussfittext2 = "Fit (sigma) = ("  + "{:.1f}".format(popt2[1]) + ")"
#    npositivetext2 = ">" + "{:d}".format(threshold_sd_margin) + "SD (>" + "{:.1f}".format(threshold2) +") : " + "{:d}".format(len(ypositive2)) + "/" + "{:d}".format(len(data))
#    info_text = "\n".join([outrangetext, gaussfittext, npositivetext, gaussfittext2, npositivetext2])
#


    #右上のテキスト
    if(manual_thresholding):
        gaussfittext = "Manual threshold : " + "{:.1f}".format(manual_threshold)
    else:
        gaussfittext = "Fit (mu,sigma) = (" + "{:.1f}".format(popt[1]) + ", " + "{:.1f}".format(popt[2]) + ")"
    npositivetext = ">" + "{:d}".format(threshold_sd_margin) + "SD (>" + "{:.1f}".format(threshold) +") : " + "{:d}".format(len(ypositive)) + "/" + "{:d}".format(len(data))
    npositivetext = npositivetext + "\n" + df2wR.histo_description
    
    outrangesum = len(list(filter(lambda x: x > plotxmax, data))) + len(list(filter(lambda x: x < plotxmin, data)))
    outrangetext = "{:d}".format(outrangesum) + " data points out of range"

    info_text = "\n".join([outrangetext, gaussfittext, npositivetext])
    ax.text(text_pos_x, 0.98, info_text, horizontalalignment='right', verticalalignment='top', transform=ax.transAxes)
     
    #使用したcsvのファイル名（複数ファイル結合時）
    if(multiple_files):
        peakint_filenames_text = "\n".join([filename_peakint_list[k] for k in peakint_df_numbers])
        plt.text(0, -0.20, peakint_filenames_text, horizontalalignment='left', verticalalignment='top', transform=ax.transAxes)
    
    #ROG vs int 散布図
    
    ax2 = fig.add_subplot(spec[1])
    ax2.scatter(df2["PeakIntensity"], df2["ROG"], s=5 , color="none", edgecolors=df2wR.histocolors[0], linewidths=0.5, alpha = 0.3)
    ax2.scatter(df2wR.rog_pos_data["PeakIntensity"], df2wR.rog_pos_data["ROG"], s=5 ,  alpha = 0.5, color="none", edgecolors=df2wR.histocolors[1], linewidths=0.3 )
    ax2.scatter(df2positive_introg["PeakIntensity"], df2positive_introg["ROG"], s=5 ,  alpha = 1, color="none", edgecolors='#ae435a', linewidths=0.3 )
    
    npositivetext3 = "Intens >" + "{:.1f}".format(threshold) +" " + "\n" + "& ROG < " + "{:.1f}".format(rog_threshold) +  "\n" +  "{:d}".format(len(df2positive_introg["PeakIntensity"])) + "/" + "{:d}".format(len(df2["PeakIntensity"]))
    ax2.text(0.98, 0.98, npositivetext3, horizontalalignment='right', verticalalignment='top', transform=ax2.transAxes)
    
    ax2.set_xlabel(xlabel)
    ax2.set_ylabel("ROG")

    ax2.set_xlim(plotxmin / plotxmax_adjuster, plotxmax / plotxmax_adjuster)
    ax2.set_ylim(3,8)
    

    filepath_dir  = "/".join(filepath.split("/")[0:-1] + [""] )
    plt.savefig(filepath_dir + shorttitle +  "_ROGvsINT_" + strftime("%y%m%d%H%M", localtime()) + '.png',  dpi=result_dpi)

    plt.show()

    #結果の集計値をexport
    summary_groups = [df2positive_introg, df2negative_int]
    summary_groupnames = ["df2positive_introg", "df2negative_int"]
    summary_groupcond = ["Intens >" + "{:.1f}".format(threshold) +" " + "& ROG < " + "{:.1f}".format(rog_threshold), "Intens <=" + "{:.1f}".format(threshold) ]
    list_summaryexport = [[shorttitle], [gaussfittext]]    
    for i in range (len(summary_groups)):
        list_summaryexport = list_summaryexport + [[" "]]
        list_summaryexport = list_summaryexport + [[summary_groupnames[i]],  [summary_groupcond[i]]]
        list_summaryexport = list_summaryexport + [["mean: " + "{:.1f}".format(np.mean(summary_groups[i]["PeakIntensity"]))], ["median: " + "{:.1f}".format(np.median(summary_groups[i]["PeakIntensity"]))], ["sd: " + "{:.1f}".format(np.std(summary_groups[i]["PeakIntensity"]))], ["counts: " + "{:d}".format(len(summary_groups[i]["PeakIntensity"]))]]
    title_summaryexport = shorttitle +  "_resultsummary_" + strftime("%y%m%d%H%M", localtime()) + '.txt'   
    with open(filepath_dir + title_summaryexport, "w") as output:
        writer = csv.writer(output, lineterminator='\n')
        writer.writerows(list_summaryexport)
    
     