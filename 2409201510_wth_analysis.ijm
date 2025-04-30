/*
 * このスクリプトで使用されているImageJマクロ関数は以下を参照しています。
 * https://imagej.nih.gov/ij/developer/macro/functions.html
 *
 */


/**
 * メイン関数
 * ここから各々の画像処理を関数として呼び出して処理を行います。
 */
function main() {
	roiImgTitles = newArray();
	exportRogPrevParameters = exportRogPrevParameters_default; //230706
	detectRoiParameters = detectRoiParameters_default; //230706
	skipdialog_roiradius = false;
	

	//視野でループ
	for (fieldIdx=START_FIELD_IDX; fieldIdx<=END_FIELD_IDX; fieldIdx++) {
		print("[" + getTimestamp("yyyy-MM-dd HH:mm:ss") + "] Processing field index " + fieldIdx + "...");

		//imgIdentifier: {解析画像名}_{視野番号}_{ROI決定用チャネル番号}_{解析チャネル番号}_YYMMDDhhmm
		//結果csvファイル名、ROI出力ファイル名、ROI表示ウィンドウのタイトルに使用する文字列
		imgIdentifier = getImgIdentifier(ORIGINAL_IMG_PATH, fieldIdx, ROI_CHANNEL_IDX, ANALYSIS_CHANNEL_IDX, LOAD_ROI); 
		
		//複数視野ループの場合、何回めか 230309
		fovnumber = fieldIdx - START_FIELD_IDX;
		

		//画像読み込み
		mainImgTitle = openImage(ORIGINAL_IMG_PATH, fieldIdx);

		// ROI設定チャネルが解析チャネルと同一の場合は解析チャネルを複製してスタックの異なるチャネルとして番号を振り直す
		if (ROI_CHANNEL_IDX == ANALYSIS_CHANNEL_IDX) {
			rearrangeChannels(mainImgTitle);
		}

		//ドリフト補正処理
		if (CORRECT_DRIFT) {
			correctDrift(mainImgTitle);
		}

		//ROIの設定
		getDimensions(WIDTH, HEIGHT, CHANNELS, SLICES, FRAMES);
		if (LOAD_ROI) {
			//事前に作成されたROIファイルを読み込む場合
			roiManager("reset"); //230821
			roiFilename = findRoiFile(ROI_DIR, File.getNameWithoutExtension(ORIGINAL_IMG_PATH), fieldIdx);
			roiManager("Open", ROI_DIR + File.separator + roiFilename);
			roiManager("deselect");
			savedroipath = ROI_DIR + File.separator + roiFilename; //DUALCOLORの場合に読み込む

			//220114追加、roiCentersに位置座標を保存しておく（ROG解析に使う）
			run("Set Scale...", "distance=0 known=1 pixel=1 unit=micron global");
			roiManager("multi-measure");	
			selectWindow("Results");
			roiCxCoords = Table.getColumn("X");
			roiCyCoords = Table.getColumn("Y");
			Table.reset("Results");
			roiCentersTableTitle = "RoiCenters";
			Table.create(roiCentersTableTitle);
			Table.setColumn("X", roiCxCoords);
			Table.setColumn("Y", roiCyCoords);
			
			fovRoiPresence = fovRoiPresence + "1";
			
		} else {
			//ROIをこの解析で設定する場合
			//print("ROICHID=" + ROI_CHANNEL_IDX);
			//print("before registerRoi: " + String.join(detectRoiParameters, " ") );
			//registerRoi(mainImgTitle, ROI_CHANNEL_IDX, 1, String.join(detectRoiParameters, " "), fovnumber); //210830 ROI作成フレームを最終フレームから1に変更 230309 パラメータを繰り返し対応
			detectRoiParameters_new = registerRoi(mainImgTitle, ROI_CHANNEL_IDX, 1, detectRoiParameters, fovnumber); //210830 ROI作成フレームを最終フレームから1に変更 230309 パラメータを繰り返し対応
			detectRoiParameters = detectRoiParameters_new;
			//print("after registerRoi: " + String.join(detectRoiParameters, " ") );
			fovRoiPresence = detectRoiParameters[13];
		}
		
		thisFovRoiPresence = substring(fovRoiPresence, lengthOf(fovRoiPresence)-1, lengthOf(fovRoiPresence));
		if(thisFovRoiPresence == 1){ //240201追加。field of viewにROIがなかった時の分岐
			
			//ROIの表示
			if (SHOW_ROI){
				roiImgTitle = showRoi(mainImgTitle, ROI_CHANNEL_IDX, 1, imgIdentifier); //210830 ROI作成フレームを最終フレームから1に変更
				roiImgTitles = Array.concat(roiImgTitles, roiImgTitle);
			}
			//ROI出力
			if (SAVE_ROI){
				saveRoi(WORK_DIR, imgIdentifier+'.zip');
				savedroipath = WORK_DIR + File.separator + imgIdentifier + ".zip"; //DUALCOLORの場合に読み込む
			}
	
			//DUALCOLORの場合は二回繰り返す 230214
			if(DUALCOLOR){
				repeats = 2;
			} else {
				repeats = 1;
			}
			for(k=0;k<repeats;k++){
				if(DUALCOLOR){
					ANALYSIS_CHANNEL_IDX = ANALYSIS_CHANNELS_ARRAY[k];
					imgIdentifier = getImgIdentifier(ORIGINAL_IMG_PATH, fieldIdx, ROI_CHANNEL_IDX, ANALYSIS_CHANNEL_IDX, LOAD_ROI); 
					if(k==1){
						roiManager("reset");
						roiManager("Open", savedroipath);
						roiManager("deselect");
					}
				} 
	
				//解析チャネルに対する前処理
				preprocessChannelForAnalysis(mainImgTitle, ANALYSIS_CHANNEL_IDX);
				if(ANALYSIS_CHANNEL_WTH){
					imgIdentifier = imgIdentifier + "_WTH" + "(" + WTH_RADIUS + ")";
				}
				print(imgIdentifier);
		
				//測定処理
				resultTableTitle = measure(mainImgTitle, ANALYSIS_CHANNEL_IDX);
		
				//結果csvファイル出力
				saveResult(resultTableTitle, WORK_DIR, imgIdentifier+'.csv');
		
				//ROGプレビューの書き出し（211014追加） ROGの解析をしており、かつタイムラプスではない場合のみ
				if(EXPORT_POSITIVES){
					exportRogPrevParameters_new = exportRogPreview(mainImgTitle, ANALYSIS_CHANNEL_IDX, WORK_DIR, resultTableTitle, imgIdentifier, exportRogPrevParameters);
					for(i=0;i<3;i++){
						exportRogPrevParameters[i+3*k] = exportRogPrevParameters_new[i]; //230310->230706bugfixed mainの外でしか定義していないと個別要素の変更は不可
					}		
					
					//waitForUser;
				}
				
				//解析ログ出力 230310追加
				saveLog(WORK_DIR, imgIdentifier+'_log.txt');
							
													
			}
	
		}//fovにROIがない場合は実行しない、ここまで。240201

		//exit();
		//不要なウィンドウを閉じる、選択状態の解除、Roi Managerリセット
		//exceptionWindowTitles = Array.concat(roiImgTitles, "Log"); //terminateExcept関数を使用して閉じないウィンドウのタイトルの配列
		exceptionWindowTitles = newArray( "Log"); //terminateExcept関数を使用して閉じないウィンドウのタイトルの配列
		terminateExcept(exceptionWindowTitles);
	}

	//ROIの画像が一つ以上開かれている場合はスタックとしてまとめる <- 230309 コメントアウト
	//if (SHOW_ROI && lengthOf(roiImgTitles)>1) {
	//	stackRoiImages();
	//}
}

/**
 * 画像識別子: {解析画像名}_{視野番号}_{ROI決定用チャネル番号}_{解析チャネル番号}_YYMMDDhhmm を返却
 * 結果csvファイル、ROI出力ファイル、ROI表示時のウィンドウタイトルに使用
 * @param  originalImgPath    オリジナル画像の絶対パス
 * @param  fieldIdx           視野番号（1はじまり）
 * @param  roiChannelIdx      ROI設定チャネル番号（1はじまり）
 * @param  analysisChannelIdx 解析チャネル番号（1はじまり）
 * @return                    画像識別子
 * 220114変更　外部ROIを読み込んだ場合はROI設定チャネル番号が"Ex"になります。
 */
function getImgIdentifier(originalImgPath, fieldIdx, roiChannelIdx, analysisChannelIdx, LOAD_ROI) {
	imgIdentifierElements = newArray(
		File.getNameWithoutExtension(originalImgPath),
		IJ.pad(fieldIdx, 3),
		IJ.pad(roiChannelIdx, 1),
		IJ.pad(analysisChannelIdx, 1),
		""+getTimestamp("yyMMddHHmm")
	);
	if(LOAD_ROI){
		imgIdentifierElements[2] = "Ex";
	}
	imgIdentifier = String.join(imgIdentifierElements, "_");

	return imgIdentifier;
}

/**
 * imgPathで指定される画像（視野番号：fieldIdx）をImageJのHyperStackとして開き、開いた画像のウィンドウタイトルを返却する
 * @param  imgPath  開く画像のパス
 * @param  fieldIdx 視野番号（1はじまり）
 * @return          開いた画像のウィンドウタイトル
 */
function openImage(imgPath, fieldIdx) {

	if (""+getFileExtension(imgPath) == "tif") {
		//[tiffファイルが指定された場合] まとめてHyperStackとして読み込む
		//210427HY変更 210506HYでは入っておらず210526HYで再度追加 fieldIdxのxy位置だけを読み込むように変更した。xyごとに個別のフォルダに入れる必要なし。
		options = newArray(
			"open=\'"+imgPath + "\'", //added quotations, 211004
			"autoscale",
			"specify_range",
			"color_mode=Default",
			"view=Hyperstack",
			"stack_order=XYCZT",
			"group_files",
			"dimensions",
			"z_begin=" + fieldIdx,
			"z_end=" + fieldIdx, //230309 changed begin & end to fieldIdx, not START and END
			"z_step=1"
		);
		run("Bio-Formats Importer",  String.join(options, " "));
	} else if (""+getFileExtension(imgPath) == "nd2") {
		//[nd2ファイルが指定された場合] HyperStackとしてそのまま読み込む
		options = newArray(
			"open=\'"+imgPath + "\'", //added quotations, 211004
			"autoscale",
			"color_mode=Default",
			"view=Hyperstack",
			"stack_order=XYCZT",
			"specify_range",
			"z_begin="+fieldIdx,
			"z_end="+fieldIdx,
			"series_"+fieldIdx
		);
		run("Bio-Formats Importer", String.join(options, " "));
	} else if (""+getFileExtension(imgPath) == "vsi") {
		//[vsiファイルが指定された場合] OlympusImageJPluginを使用して読み込み
		run("Viewer", "open="+imgPath);
	} else {
		//[その他の画像形式が指定された場合] 終了する
		exit("扱うことのできない画像ファイル形式のため処理を終了します。");
	}

	openedImgTitle = getTitle();

	return openedImgTitle;
}

/**
 * 解析チャネルを別チャネルに複製し、チャネル1:ROI設定チャネル、チャネル2:解析チャネル として振り直す
 * （解析チャネルとROI設定チャネルが同一の場合に使用する関数）
 * @param  imgTitle 解析対象画像のウィンドウタイトル
 */
function rearrangeChannels(imgTitle) {
	run("Split Channels");

	//解析チャネルを複製
	analysisChannelTitle = "C"+ANALYSIS_CHANNEL_IDX+"-"+imgTitle;
	selectWindow(analysisChannelTitle);
	run("Duplicate...", "duplicate");
	newRoiChannelTitle = getTitle();
	
	//スタックとしてまとめ、元の名前を振り直す
	options = newArray(
		"c1=["+newRoiChannelTitle+"]",
		"c2=["+analysisChannelTitle+"]",
		"create"
	);
	run("Merge Channels...", String.join(options, " "));
	rename(imgTitle);
	close("\\Others");

	//チャネル番号を振り直す（Log出力には元の番号が使用される）
	ROI_CHANNEL_IDX = 1;
	ANALYSIS_CHANNEL_IDX = 2;

}

/**
 * ドリフト補正を行う
 * HyperStackReg参照先（Github）
 * https://github.com/ved-sharma/HyperStackReg
 * @param  imgTitle ドリフト補正を適用する画像のウィンドウタイトル
 */
function correctDrift(imgTitle) {

	selectWindow(imgTitle);

	//ドリフト補正に使用する基準チャネルの選択ダイアログ。220518追加。
	Stack.getDimensions(_, _, cmax, _, _);	
	Dialog.create("Drift Correction");
	Dialog.addMessage("Select reference channel to perform drift correction.");
	clist = newArray(cmax);
	for (i = 0; i < cmax; i++) {
		clist[i] = i+1;
	}
	Dialog.addChoice("Channels", clist);
	Dialog.show();
	channelfordriftcor = Dialog.getChoice();

	options = newArray(
		"transformation=[Rigid Body]",
		"channel"+channelfordriftcor
	);
	run("HyperStackReg ", String.join(options, " "));

	//チャネル合成表示->チャネル個別表示 切り替え
	Stack.setDisplayMode("color");

	//補正前の画像は削除し、補正後の画像に同じ名前をつけ直す
	close(imgTitle);
	rename(imgTitle);
}

/**
 * targetDirで指定されるディレクトリの中からROIファイルを名前で検索し、ヒットしたファイル名を返却する
 * @param  targetDir                           ROIファイル検索先ディレクトリ
 * @param  originalImgFilenameWithoutExtension オリジナル画像のファイル名（拡張子なし）
 * @param  fieldIdx                            視野番号
 * @return                                     ROIファイル名
 */
function findRoiFile(targetDir, originalImgFilenameWithoutExtension, fieldIdx) {
	filenames = getFileList(targetDir);

	//*****rule変数は任意に書き換え可能です。*****
	//ROIファイル名ルール: {画像ファイル名}_{視野番号}{任意の0文字以上の文字列}.zip
	//
	//画像ファイル名: sample.nd2, 視野番号: 1 の場合の例
	//・変数ruleに代入される文字列（正規表現）: "^sample_0*1.*\.zip$"
	//・自動読み込み可能なファイル名
	//  例1: sample_001_1_2_2009221718.zip （この解析スクリプトから出力されるROIファイルを読み込み可能です）
	//  例2: sample_001.zip （視野番号から後ろの文字列の有無、内容は無視されます）
	//  例3: sample_1.zip （視野番号の0埋めの有無、桁数は無視されます）
	//  (220114追加ルール）"c3_"もしくは"c3."の形でチャネル番号がファイル名に含まれていた場合は、cの後の数字はなんでもいいことにします
	rule = "^"+originalImgFilenameWithoutExtension+"_0*"+fieldIdx+".*\\.zip$";
	rule = replace(rule, "c[0-9][_\\.]", "c.."); //220114追加ルール
	//*************

	//指定されたディレクトリのファイル群の中から最初にルール（正規表現）に合致したファイル名を選び出す
	//220114複数ある場合は選択肢を表示するように変更
	roiFilename = "";
	roiFileCandidates = newArray(lengthOf(filenames));
	j=0;
	for (i=0; i<lengthOf(filenames); i++) {
		if (filenames[i].matches(rule)) {
			roiFileCandidates[j] = filenames[i];
			j++;		
		}
	}

	if (j==0) {
		exit("読み込み可能なROIファイルがありません。以下の項目をご確認ください。\n \n・パラメータ設定で指定したROIファイル読み込み元ディレクトリが正しいかどうか\n・ROIファイル名が命名規則: {画像ファイル名}_{視野番号}{任意の0文字以上の文字列}.zip に則っているか\n\nrule=" + rule);
	} else if (j>1){
		roiFileCandidates = Array.trim(roiFileCandidates, j); 
		Dialog.create("Select ROI file");
		Dialog.addMessage("2 or more matches found. Choose the roi file to use.");
		Dialog.addChoice("ROI candidates", roiFileCandidates);
		Dialog.show();
		roiFilename = Dialog.getChoice();
	} else {
		roiFilename = roiFileCandidates[0];
	}

	return roiFilename;
}

/**
 * ROI設定チャネルの前処理、解析対象範囲設定、ROI中心検出、ROI Managerへの登録 の一連の処理を実行する
 * @param  imgTitle   ROI設定に使用する画像のウィンドウタイトル
 * @param  channelIdx ROI設定に使用するチャネル番号
 * @param  timepoint  ROI設定に使用するtimepoint
 */
function registerRoi(imgTitle, channelIdx, timepoint, detectRoiParameters, fovnumber) {	

	//ROI設定チャネルに対する前処理
	preprocessChannelForRoiDefinition(imgTitle, channelIdx, timepoint);
	channelIdx = ROI_CHANNEL_IDX;

	//解析対象範囲の設定
	detectRoiParameters_new3 = setRoiSettingArea(mainImgTitle, detectRoiParameters);

	//ROI中心の検出
	detectRoiParameters_new = detectRoiCenters(imgTitle, channelIdx, detectRoiParameters_new3,  timepoint,  fovnumber);

	roiCentersTableTitle = detectRoiParameters_new[3];
	fovRoiPresence = detectRoiParameters_new[13];
	thisFovRoiPresence = substring(fovRoiPresence, lengthOf(fovRoiPresence)-1, lengthOf(fovRoiPresence));
	
	//waitForUser("thisFovRoiPresence = " + thisFovRoiPresence);

	if(thisFovRoiPresence == "1"){ //240201追加。field of viewにROIがなかった時の分岐
		//waitForUser("again, thisFovRoiPresence = " + thisFovRoiPresence);
		//220601追加。ビーズELISAモードでは、ビーズの判定を行う。
		if(BEADSELISA){
			detectRoiParameters_new2 = findBeadsFromBF(imgTitle, roiCentersTableTitle, detectRoiParameters_new, fovnumber);
			detectRoiParameters_new = detectRoiParameters_new2;
		}
		

		wait(500);
	
		//ROI ManagerへのROIの登録
		detectRoiParameters_new2 = setRoi(roiCentersTableTitle, detectRoiParameters_new, fovnumber);
		detectRoiParameters_new = detectRoiParameters_new2;

	} else {
		wait(10);
	}
	
	return detectRoiParameters_new;
}

/**
 * imgTitleで指定される画像の、 チャネル=channelIdx, タイムポイント=timepoint に対して前処理を施す
 * ROI設定チャネル画像用
 * @param  imgTitle   前処理を適用する画像のウィンドウタイトル
 * @param  channelIdx 前処理を適用するチャネル番号（1はじまり）
 * @param  timepoint  前処理を適用するタイムポイント番号（1はじまり）
 */
function preprocessChannelForRoiDefinition(imgTitle, channelIdx, timepoint) {
	selectWindow(imgTitle);

	Stack.setPosition(channelIdx, 1, timepoint);
	//waitForUser;

	//ここにROI設定チャネルに適用する任意の前処理を記述------------------
	//run("Subtract Background...", "rolling=50");
	// run("Gaussian Blur...", "sigma=2");
	// run("Median...", "radius=2");
	
	run("Duplicate...", " ");
	rename(imgTitle+"_roich_original"); //screenregion用。240130
	selectWindow(imgTitle);
	//waitForUser("check roich_original");
	wthRoiChannel(imgTitle, channelIdx, 5);

	//ここまで-----------------------------------------------
}
/**
 * WTH, median, meanをROIchannelに噛ませる。
 * 新しくstack作り直す。
 * 210318に追加。柳沼
 * 210506に、channel数が2,3の場合に対応
 * 211012 WTHの前にmedian rad 1px, mean rad 1pxをやるように変更した。また、WTHの形状はsquareにした。
 * 211013 wth半径はWTH-RADIUSで最初に指定
 */
function wthRoiChannel(imgTitle, channelIdx, wthradius){
		
	imgTitle;
	Stack.getDimensions(width, height, cmax, slices, frames);
	
	run("Split Channels");
	selectWindow("C" + channelIdx + "-"+imgTitle);
	tempID = getTime();
	getDimensions(width, height, channels, slices, frames);
	for(i=0;i<frames;i++){
		selectWindow("C" + channelIdx + "-"+imgTitle);
		setSlice(i+1);
		run("Duplicate...", " ");
		rename("temp" + tempID + "-duplicate");
		if(BEADSELISA){
			run("Gaussian Blur...", "sigma=2");
			run("Median...", "radius=2");
		} else {
			run("Median...", "radius=1 stack");
			run("Mean...", "radius=1 stack");
		}
		run("Morphological Filters", "operation=[White Top Hat] element=Square radius=" + wthradius);
		rename("temp" + tempID + "-" + (i+1));
		close("temp" + tempID + "-duplicate");
		if(i==9){ //220517 frames>=10の時の処理を変更しwindow総数が増えすぎないようにした。
			run("Images to Stack", "method=[Copy (center)] name=Stack" + tempID + " title=temp" + tempID);
		} else if (i>9){
			run("Concatenate...", "title=Stack" + tempID + " image1=Stack" + tempID + " image2=temp" + tempID + "-" + (i+1) + " image3=[-- None --]");
		}
	}
	if(frames<10){
		run("Images to Stack", "method=[Copy (center)] name=Stack" + tempID + " title=temp" + tempID);
	}

	close("C" + channelIdx + "-" + imgTitle);
	selectWindow("Stack"+tempID);
	rename("C" + channelIdx + "-" + imgTitle);
	
	options = newArray(
		"image1=["+"C1-" + imgTitle +"]",
		"image2=["+"C2-" + imgTitle +"]",
		"image3=["+"C3-" + imgTitle +"]",
		"image4=["+"C4-" + imgTitle +"]",
		"image5=[-- None --]"
	);
	if(cmax < 4){
		options[cmax] = "image" + cmax+1 + "=[-- None --]";
	}
	run("Concatenate...", String.join(options, " "));
	run("Stack to Hyperstack...", "order=xytzc channels=" + CHANNELS + " slices=" + SLICES + " frames=" + FRAMES + " display=Color");
	rename(imgTitle);
	close("C*-" + imgTitle);

}


/**
 * ROI設定可能範囲を指定する
 * この関数を呼び出すことでROI設定可能範囲が選択状態になる
 *
 * 以下の変数は任意に変更可能です
 * radius: 解析対象範囲の半径（単位pixel）
 * @param  imgTitle 画像の幅、高さを測定するために使用する画像のタイトル
 */
function setRoiSettingArea(imgTitle, detectRoiParameters) {
	selectWindow(imgTitle);
	getDimensions(width, height, _, _, _);
	screenregion_use_erosion = detectRoiParameters[14];
	screenregion_erosion_radius = detectRoiParameters[15];
	screenregion_roich_lower = detectRoiParameters[16];
	screenregion_roich_upper = detectRoiParameters[17];
	skipdialog_screenregion = detectRoiParameters[18];
	

	if(SCREENREGION == "全画面解析" || SCREENREGION == "輝度値範囲指定"){
		edge = 8;
		makeRectangle(edge, edge, width-edge*2, height-edge*2);
		
	} else if (SCREENREGION == "中央円形領域解析"){
		radius = width * 3 / 8; //解析対象範囲の半径（単位pixel）
		//画像中心の座標(imgCx, imgCy)（cx, cyはcenter x, center yの略）
		imgCx = round(width / 2);
		imgCy = round(height / 2);
		diameter = radius * 2;
		makeOval(imgCx-radius, imgCy-radius, diameter, diameter);
	} else {
		waitForUser("Create region (rectangle, oval, polygon or freehand) to perform analysis");
		if(selectionType() < -1){
			showMessage("Please set a valid ROI for analysis.");
		} else if (selectionType() > 3){
			showMessage("Please set a valid ROI (rectangle, oval, polygon or freehand) for analysis.");
		}
	}
	newImage(imgTitle + "RoiSettingArea", "8-bit black", width, height, 1);
	run("Restore Selection");
	setColor(255);
	fill();
	if (SCREENREGION == "輝度値範囲指定"){ //240130 ROI設定チャネルの輝度値で解析有効範囲を指定できるようにした
		selectWindow(imgTitle+"_roich_original");
		Stack.setPosition(ROI_CHANNEL_IDX,1,1);
		run("Duplicate...", " ");
		rename(imgTitle + "RoiSettingArea2");
		
		if(skipdialog_screenregion == false){
			Dialog.create("Analyze areas where ROI_CH signal are within a user-defined range");
			Dialog.addCheckbox("Apply erosion filter to ROI channel (recommended)", screenregion_use_erosion);
			Dialog.addNumber("erosion filter radius", screenregion_erosion_radius);
			Dialog.addNumber("ROI-CH intensity lower limit", screenregion_roich_lower);
			Dialog.addNumber("ROI-CH intensity upper limit", screenregion_roich_upper);
			Dialog.addCheckbox("Skip dialog and use the same settings for the rest of the slices.", false);
			Dialog.show();
			screenregion_use_erosion = Dialog.getCheckbox();
			screenregion_erosion_radius = Dialog.getNumber();
			screenregion_roich_lower = Dialog.getNumber();
			screenregion_roich_upper = Dialog.getNumber();
			skipdialog_screenregion = Dialog.getCheckbox();			
		}
		
		if(screenregion_use_erosion){
			run("Morphological Filters", "operation=Erosion element=Disk radius=" + screenregion_erosion_radius);
			rename("erosion");
			close(imgTitle + "RoiSettingArea2");
			selectWindow("erosion");
			rename(imgTitle + "RoiSettingArea2");
		}
		setThreshold(screenregion_roich_lower, screenregion_roich_upper, "raw");
		run("Convert to Mask", "method=Li background=Light black");
		
		imageCalculator("Multiply", imgTitle + "RoiSettingArea",imgTitle + "RoiSettingArea2");
		wait(10);
		//close(imgTitle + "RoiSettingArea2"); //240920
		close(imgTitle + "_roich_original");
	} else {
		screenregion_use_erosion = false;
		screenregion_erosion_radius = -1;
		screenregion_roich_lower = -1;
		screenregion_roich_upper = -1;
	}

	selectWindow(imgTitle);
	detectRoiParameters_new = detectRoiParameters;
	detectRoiParameters_new[14] = screenregion_use_erosion;
	detectRoiParameters_new[15] = screenregion_erosion_radius;
	detectRoiParameters_new[16] = screenregion_roich_lower;
	detectRoiParameters_new[17] = screenregion_roich_upper;
	detectRoiParameters_new[18] = skipdialog_screenregion;
	return detectRoiParameters_new;
}

/**
 * imgTitle, channelIdx, timepointで指定された画像を使用してROI中心を検出し、
 * 全てのROI中心座標が記録されたテーブルのウィンドウタイトルを返却する
 * @param  imgTitle   ROI検出を行う画像タイトル
 * @param  channelIdx ROI検出を行うチャネル番号（1はじまり）
 * @param  timepoint  ROI検出を行うタイムポイント番号（1はじまり）
 * @return            全てのROI中心座標が記録されたテーブルのウィンドウタイトル
 * 221011 チャンバー検出がうまくいかないときのために、ROI検出チャネルを一時的にGaussian blurする機能を追加
 */
function detectRoiCenters(imgTitle, channelIdx, detectRoiParameters,  timepoint,  fovnumber) {
//detectRoiParameters: prom, maximaok, roichblur, roicenterstabletitle, roiRadius 230309
	Array.show(detectRoiParameters);
	prom = detectRoiParameters[0];
	maximaok = false;
	roichblur = detectRoiParameters[2];
	roiCentersTableTitle = detectRoiParameters[3];
	fovRoiPresence = detectRoiParameters[13];
	skipdialog_findmaxima = detectRoiParameters[19];
	//230309

	selectWindow(imgTitle);
	Stack.setPosition(channelIdx, 1, timepoint);

	run("Set Measurements...", "centroid");
	run("Set Scale...", "distance=0 known=1 pixel=1 unit=micron global");

	//ここにROI中心検出処理を記述------------------
	//*****極大点検出パターン例*****
	
	while(maximaok == false){
		Stack.setPosition(channelIdx, 1, timepoint);
		roiManager("reset");
		if(roichblur == "Yes (2px)"){
			run("Select None");
			run("Duplicate...", " ");
			rename("blur");
			run("Gaussian Blur...", "sigma=2");
			//setRoiSettingArea("blur"); //240130以降不要のはず
			wait(200);
		}
		run("Enhance Contrast", "saturated=2");
		run("To Selection");
		run("In [+]");
		run("In [+]");
		run("In [+]");
		run("Find Maxima...", "prominence=" + prom + " output=[Point Selection]");
		if(roichblur == "Yes (2px)"){
			selectWindow(imgTitle);
			run("Restore Selection");
			Stack.setPosition(channelIdx, 1, timepoint);
			close("blur");
		}
		
		//240130 filter multi-points (from here)
		selectWindow(imgTitle + "RoiSettingArea");
		run("Restore Selection");
		Roi.getCoordinates(xcandidates, ycandidates);
		nPoints = lengthOf(xcandidates);
		xcoords = newArray(nPoints);
		Array.fill(xcoords, -1);
		ycoords = newArray(nPoints);
		Array.fill(ycoords, -1);
		j = 0;		
		for (i = 0; i < nPoints; i++) {
			x = xcandidates[i];
			y = ycandidates[i];
			if(getValue(x, y) == 255){
				xcoords[j] = x;
				ycoords[j] = y;
				j++;
			}
		}
		print(j + " / " + nPoints);
		xcoords = Array.trim(xcoords, j);
		ycoords = Array.trim(ycoords, j);
		makeSelection("point", xcoords, ycoords);
		selectWindow(imgTitle);
		run("Restore Selection");

		//240130 filter multi-points (end)
		
		//240201 skip if no valid ROI
		if(j>0){
			fovRoiPresence = fovRoiPresence + "1";
			roiManager("add");
		} else {
			fovRoiPresence = fovRoiPresence + "0";
		}
		
		
		if(skipdialog_findmaxima == false){ 
			waitForUser("Check point selection and click OK.");
	
			Dialog.create("Find Maxima");
			Dialog.addCheckbox("Check here before pressing OK if wish to do Find Maxima again", false);
			Dialog.addNumber("Prominence", prom);
			Dialog.addNumber("Change slice position to set ROI", timepoint);
			Dialog.addRadioButtonGroup("Apply Gaussian Blur to ROI channel", newArray("No", "Yes (2px)"), 2, 1, roichblur);
			Dialog.addMessage("If you wish to proceed with current selected points, just click OK.");
			Dialog.addMessage(" ");
			Dialog.addCheckbox("Skip dialog and use the same settings for the rest of the slices", false);
			Dialog.show();
			maximaok = ! Dialog.getCheckbox();
			//print(maximaok);
			prom = Dialog.getNumber();
			timepoint = Dialog.getNumber();
			roichblur = Dialog.getRadioButton();
			skipdialog_findmaxima = Dialog.getCheckbox(); //skip 240201
			if(skipdialog_findmaxima){
				maximaok = false;
			}
			run("Select None");
		} else {
			maximaok = true;
			run("Select None");
		}
		//setRoiSettingArea(mainImgTitle); //240130以降不要のはず
	}
	//waitForUser;

	//*****極大点検出ここまで*****

	//*****円検出使用パターン例*****
	//setAutoThreshold("Default dark"); // 二値化
	//run("Analyze Particles...", "size=5-50 circularity=0.50-1.00 display exclude clear add"); //円検出
	//waitForUser;

	// *****円検出ここまで*****
	//ここまで-------------------------------------
	if(j>0){
		//waitForUser("before multi-measure");
		run("Restore Selection");
		roiManager("multi-measure");
		roiManager("reset");
		
		selectWindow("Results");
		roiCxCoords = Table.getColumn("X");
		roiCyCoords = Table.getColumn("Y");
		Table.reset("Results");
	} else {
		roiCxCoords = newArray(0);
		roiCyCoords = newArray(0);
	}

	roiCentersTableTitle = "RoiCenters";
	Table.create(roiCentersTableTitle);
	Table.setColumn("X", roiCxCoords);
	Table.setColumn("Y", roiCyCoords);
	
	close(imgTitle + "RoiSettingArea2"); //240920 for debugging
	detectRoiParameters_new = detectRoiParameters;
	detectRoiParameters_new[0] = prom; //230309
	detectRoiParameters_new[1] = maximaok; //230309
	detectRoiParameters_new[2] = roichblur; //230309
	detectRoiParameters_new[3] = roiCentersTableTitle; //230309
	detectRoiParameters_new[13] = fovRoiPresence; //240201
	detectRoiParameters_new[19] = skipdialog_findmaxima; //240201
	//detectRoiParameters[4] = detectRoiParamters[4]; //230309

	return detectRoiParameters_new;//roiCentersTableTitle;
}

/**
 * ROI中心座標の情報を使用してROIをRoiManagerに登録する
 *
 * 以下の変数は任意に変更可能です
 * roiRadius: ROIの半径（単位pixel）
 * @param  roiCentersTableTitle ROI中心の座標が記録されたテーブルのタイトル
 */
function setRoi(roiCentersTableTitle, detectRoiParameters, fovnumber) {

	selectWindow(roiCentersTableTitle);
	roiRadius = detectRoiParameters[4];
	skipdialog_roiradius = detectRoiParameters[20];
	detectRoiParameters_new = detectRoiParameters;
	if(skipdialog_roiradius == false){ //230309
		// ROIの半径（単位ピクセル）
		Dialog.create("Select ROI radius");
		label = "Conditions";
		items = newArray("5px (microscope 20x obj, CYTOP device)", "3px (microscope 20x obj, ICS device)", "1px (peak center), any device");
		Dialog.addRadioButtonGroup(label, items, lengthOf(items), 1, items[0]);
		Dialog.addCheckbox("Skip dialog and use thesame settings.", false);
		Dialog.show();
		radiusChoice = Dialog.getRadioButton();
		if(radiusChoice == items[0]){
			roiRadius = 5;
		} else if(radiusChoice == items[1]){
			roiRadius = 3;
		} else {
			roiRadius = 1;
		}
		skipdialog_roiradius = Dialog.getCheckbox();
	} 
	selectWindow(roiCentersTableTitle); //210526HY

	nRois = Table.size;
	print(nRois);
	print(getTitle);
	roiCxCoords = Table.getColumn("X");
	roiCyCoords = Table.getColumn("Y");
	
	roiDiameter = roiRadius * 2;
	for (roiIdx=0; roiIdx<nRois; roiIdx++) {
		roiCx = roiCxCoords[roiIdx];
		roiCy = roiCyCoords[roiIdx];

		print("roiCx:"+roiCx + " roiCy:"+roiCy + " roiRad:"+roiRadius + " roiDiameter:"+roiDiameter);
		makeOval(roiCx-roiRadius, roiCy-roiRadius, roiDiameter, roiDiameter);

		roiManager("add");
	}
	roiManager("deselect");
	
	detectRoiParameters_new[4] = roiRadius;
	detectRoiParameters_new[20] = skipdialog_roiradius;
	
	return detectRoiParameters_new;
}

//220601 ビーズELISAのために、明視野画像からビーズの入っているチャンバーを判定したバイナリ画像を作成する。
//画像処理後のビーズ部分の面積で判定する。２個連結している物なども面積基準で除外する。判定のThresholdは現状半自動、一部人の目で設定する。
function findBeadsFromBF(imgTitle, roiCentersTableTitle, detectRoiParameters, fovnumber){ 
	//findBeadsParameters: minarea, maxarea, tolerance, invertedanalysis, BTHradius, closingradius 230829
	//detectRoiParameters: x, x, x, x, x,  channelBFnumber, minarea, maxarea, tolerance,. 230309
	channelBF = detectRoiParameters[5];
	areamin = detectRoiParameters[6];
	areamax = detectRoiParameters[7];
	tolerance = detectRoiParameters[8];
	doinvertedanalysis = detectRoiParameters[9];
	beadBTHradius = detectRoiParameters[10];
	beadclosingradius = detectRoiParameters[11];
	beadThreshold = detectRoiParameters[12];
	
	selectWindow(imgTitle);
	Stack.getDimensions(width, height, cmax, _, _);	

	if(fovnumber==0){
		//明視野チャネルの選択ダイアログ。		
		Dialog.create("Find beads from BF");
		Dialog.addMessage("Select BF channel to perform beads detection.");
		clist = newArray(cmax);
		for (i = 0; i < cmax; i++) {
			clist[i] = i+1;
		}
		Dialog.addChoice("Channels", clist, clist[channelBF-1]);
		Dialog.addMessage("Set parameters for bead detection, if necessary.");
		Dialog.addNumber("Radius of background subtraction", beadBTHradius);
		Dialog.addNumber("Radius of closing", beadclosingradius);
		thres_names = getList("threshold.methods");
		Dialog.addChoice("Threshold method", thres_names, "Otsu");
		Dialog.addNumber("Min area", areamin);
		Dialog.addNumber("Max area", areamax);
		Dialog.addMessage("注意：いまのところタイムラプスデータに対応はしていません。");
		Dialog.show();
		channelBF = Dialog.getChoice();
		beadBTHradius = Dialog.getNumber();
		beadclosingradius = Dialog.getNumber();
		beadThreshold = Dialog.getChoice();
		areamin = Dialog.getNumber();
		areamax = Dialog.getNumber();		
	}
	
	//明視野チャネルの複製
	Stack.setPosition(channelBF, 1, 1);
	run("Duplicate...", " ");
	run("Grays");
	rename("imageBF");
	
	//black top hat処理
	run("Morphological Filters", "operation=[Black Top Hat] element=Disk radius=" + beadBTHradius); //230829
	rename("imageBF-BTH");
	setAutoThreshold(beadThreshold + " dark");
	
	//closing処理で細かい凹凸をなくす
	run("Morphological Filters", "operation=Closing element=Disk radius=" + beadclosingradius); //230829
	rename("imageBF-BTH-closing");
	setAutoThreshold(beadThreshold + " dark");
	
	//Particle解析で物体の面積を出す
	//run("Analyze Particles...", "size=2-100 show=Overlay exclude clear add");
	run("Analyze Particles...", "size=" + areamin + "-" + areamax + " show=Overlay exclude clear add"); //230829 2-100を2-500に変更
	selectWindow("imageBF");
	run("Set Measurements...", "area mean min centroid center perimeter redirect=None decimal=3");
	run("Clear Results");
	roiManager("Deselect");
	roiManager("Measure");
	String.copyResults();
	if(fovnumber==0){ //繰返し時は一回めだけ 230309
		//面積範囲を手動で指定
		Dialog.create("Bead area threshold");
		Dialog.addMessage("ビーズらしき物体の情報をクリップボードにコピーしました。\nNumbersなどでグラフ化し、ELISA解析に有効なビーズと判定する面積の範囲を決定して、以下に入力してください。\nData of bead-like objects are saved to clipboard.\nSet area threshold for singlet bead detection.");
		Dialog.addNumber("Min area", areamin);
		Dialog.addNumber("Max area", areamax);
		Dialog.addMessage("このマクロで解析している物体の面積範囲は" + areamin + "-" + areamax + "です。");
		Dialog.addNumber("tolerance (pixels)", tolerance);
		Dialog.addMessage("toleranceは原則0です。ただし、ch間でチャンバー位置がずれてしまっている場合には、ずれているpx分の値を入力してください。");
		Dialog.addCheckbox("inverted analysis", doinvertedanalysis);
		Dialog.addMessage("ビーズのあるチャンバーを除外してビーズのないチャンバーを解析する場合は、inverted analysisにチェックを入れてください。");
		Dialog.show();
		areamin = Dialog.getNumber();
		areamax = Dialog.getNumber();
		tolerance = Dialog.getNumber();	
		doinvertedanalysis = Dialog.getCheckbox();
	}
	
	//面積範囲に入らなかったROIを消去
	nRois = roiManager("count");
	for(i=nRois-1;i>=0;i--){
		roiManager("select", i);
		roiarea = getResult("Area", i);
		if(roiarea < areamin || roiarea > areamax){
			roiManager("delete");
		}
	}

	//有効のビーズを示す画像を作成
	newImage(imgTitle + "DetectedBead", "8-bit black", width, height, 1);
	nRois = roiManager("count");
	for(i=0;i<nRois;i++){
		roiManager("select", i);
		setForegroundColor(255, 255, 255);
		setBackgroundColor(0, 0, 0);
		run("Fill", "slice");
	}
	
	//tolerance > 0の場合、DetectedBead画像をdilationして引っかかりやすくしておく
	if(tolerance>0){
		run("Morphological Filters", "operation=Dilation element=Disk radius=" + tolerance);
		titledil = getTitle();
		close(imgTitle + "DetectedBead");
		selectWindow(titledil);
		rename(imgTitle + "DetectedBead");
	}
	
	//いらないものを消す
	run("Select None");
	roiManager("reset");
	run("Clear Results");
	close("imageBF*");
	
	//有効ROI位置のテーブルを作り直す
	selectWindow(roiCentersTableTitle); 
	nRois = Table.size;
	roiCxCoords = Table.getColumn("X");
	roiCyCoords = Table.getColumn("Y");
	selectWindow(imgTitle + "DetectedBead");
	nBead = 0;
	for(i=0;i<nRois;i++){
		value = getPixel(roiCxCoords[i], roiCyCoords[i]);
		setPixel(roiCxCoords[i], roiCyCoords[i], 128);
		if(doinvertedanalysis){ //ビーズのないチャンバーの解析をする場合
			if(value!=0){
				nBead++;
				roiCxCoords[i]=-1;
				roiCyCoords[i]=-1;
			}			
		} else {
			if(value!=0){
				nBead++;
			} else {
				roiCxCoords[i]=-1;
				roiCyCoords[i]=-1;
			}			
		}	

	}
	roiCxCoords = Array.deleteValue(roiCxCoords, -1);
	roiCyCoords = Array.deleteValue(roiCyCoords, -1);
	close(roiCentersTableTitle);
	Table.create(roiCentersTableTitle);
	Table.setColumn("X", roiCxCoords);
	Table.setColumn("Y", roiCyCoords);
	
	detectRoiParameters_new = detectRoiParameters;
	detectRoiParameters_new[5] = channelBF;
	detectRoiParameters_new[6] = areamin;
	detectRoiParameters_new[7] = areamax;
	detectRoiParameters_new[8] = tolerance;
	detectRoiParameters_new[9] = doinvertedanalysis;
	detectRoiParameters_new[10] = beadBTHradius;
	detectRoiParameters_new[11] = beadclosingradius;
	detectRoiParameters_new[12] = beadThreshold;
	
	return detectRoiParameters_new;
	
}

/**
* Roi managerに登録されているROIををウィンドウに表示し、ウィンドウタイトルを返却する
 * @param  imgTitle      ROI表示のために複製して使用する画像のウィンドウタイトル
 * @param  roiChannelIdx ROI表示に使用する画像のチャネル番号（1はじまり）
 * @param  timepoint     ROI表示に使用する画像のタイムポイント（1はじまり）
 * @param  imgIdentifier 画像識別子
 * @return               ROIが表示されたウィンドウのタイトル
 */
function showRoi(imgTitle, roiChannelIdx, timepoint, imgIdentifier) {
	selectWindow(imgTitle);

	run("Select None");

	//ROI表示用の画像作成
	options = newArray(
		"duplicate",
		"channels="+roiChannelIdx,
		"frames="+timepoint
	);
	run("Duplicate...", String.join(options, " "));
	run("Enhance Contrast...", "saturated=0"); //見やすさのために画像を標準化
	roiManager("Set Color", "cyan");
	roiManager("Show All without labels");
	wait(500);
	run("Flatten");

	roiImageTitle = "roi_" + imgIdentifier;
	rename(roiImageTitle);

	return roiImageTitle;
}

/**
 * Roi managerに登録されているROIをzipファイルとして保存する
 * @param  workDir  zipファイル出力先のディレクトリ
 * @param  filename 保存するファイル名
 */
function saveRoi(workDir, filename) {
	roiManager("save", workDir + File.separator + filename);
}

/**
 * imgTitle, channelIdxで指定された画像に対して前処理を施す
 * 解析チャネル画像用
 * @param  imgTitle   前処理を行う画像のウィンドウタイトル
 * @param  channelIdx 前処理を行うチャネル番号（1はじまり）
 */
function preprocessChannelForAnalysis(imgTitle, channelIdx) {
	selectWindow(imgTitle);
	Stack.setPosition(channelIdx, 1, 1);
	
	//ここに解析チャネルに適用する任意の前処理を記述------------------
	// backGroundImgFile = "/path/to/background_image.tif"; //ムラ補正画像の絶対パス
	// open(backGroundImgFile);
	// backGroundImgTitle = getTitle();
	//
	// referenceImgFile = "/path/to/reference_image.tif"; //ムラ補正画像の絶対パス
	// open(referenceImgFile);
	// referenceImgTitle = getTitle();
	//
	// // (image-background) / (reference-background)
	// imageCalculator("Subtract stack", imgTitle, backGroundImgTitle);
	// imageCalculator("Subtract", referenceImgTitle, backGroundImgTitle);
	// imageCalculator("Divide 32-bit stack", imgTitle, referenceImgTitle);
	if(ANALYSIS_CHANNEL_WTH){
		wthRoiChannel(imgTitle, channelIdx, WTH_RADIUS); //解析チャネルにWhite Top Hatをかける。
	}
	//ここまで------------------------------------------------
}

/**
 * 211012追加、長方形選択範囲内のモーメントの計算用のマクロ
 * p, qはそれぞれモーメントの次数（x, y）
 */
function selectionMoment(p, q){
	getSelectionBounds(x0, y0, width, height);
	//getDimensions(width, height, channels, slices, frames);
	momarray = newArray(width * height);
	for(y=0;y<height;y++){
		for(x=0;x<width;x++){
			xi = x0 + x;
			yi = y0 + y;
			momarray[y*width + x] = pow(x - (width - 1)/2, p) * pow(y - (height - 1)/2, q) * getPixel(xi, yi);
		}
	}

	sum_array = 0;
	for(i=0;i<height*width;i++){
		sum_array = sum_array + momarray[i];
	}

	return sum_array;
	
}


/**
 * 211012追加、長方形選択範囲内のROG計算のマクロ
 */
function selectionRog(){
	m00 = selectionMoment(0,0);
	m20 = selectionMoment(2,0);
	m02 = selectionMoment(0,2);
	rog = sqrt((m20 + m02)/m00);
	return rog;

}

//Timelapse観察の結果にはまだ対応していない。時間軸のない場合にのみ有効。211014追加。
function exportRogPreview(imgTitle, channelIdx, workDir, resultTableTitle, imgIdentifier, exportRogPrevParameters){
	//240201 exportRogPrevParameters  thresRogUL, thresIntLL, saveRogRoi, _, _, _, skipdialog
	thresholdRog = exportRogPrevParameters[0];
	thresholdInt = exportRogPrevParameters[1];
	saveRogRoi = exportRogPrevParameters[2];	
	skipdialog_exportrog = exportRogPrevParameters[6];
	intRangeMin = exportRogPrevParameters[7];
	intRangeMax = exportRogPrevParameters[8];
		
	selectWindow(imgTitle);
	getDimensions(width, height, channels, slices, frames);
	if(slices > 1 || frames > 1){
		showMessage("タイムラプスデータなどのスタックに対するROG判定プレビュー画像の書き出しにはまだ対応していません。2021.10.14 柳沼");
		exportRogPrevParameters_new = exportRogPrevParameters;
	} else {
		exportRogPrevParameters_new = exportRogPrevParameters;
		Stack.setPosition(channelIdx, 1, 1);
		run("Select None");
		run("Duplicate...", " ");
		rename("rogpreview");
		selectWindow("rogpreview");
		setMinAndMax(intRangeMin, intRangeMax);
		run("Green");

		roiManager("select", 0);
		Roi.getBounds(_, _, roiDiameter, _);
		
		roiManager("reset");
		//open(workDir + File.separator + imgIdentifier + ".csv");
		tableName = resultTableTitle;
		selectWindow(tableName);
		nRows = Table.size ;
		print(nRows);
		
		if(skipdialog_exportrog == false){
			Dialog.create("Make positives preview image"); //240920 change dialog name and allow intensity only preview
			Dialog.addMessage("Enter ROG upper limit value you are going to use in the following analysis step.　Recommended: 5.5");
			if(CALCULATE_ROG == false){
				Dialog.addMessage("!! ROG caluculation is set to false, so this value will be ignored.", 12, "#ff0000");				
			}
			Dialog.addNumber("threshold of ROG (upper limit)", thresholdRog);
			Dialog.addMessage("\nEnter Intensity lower limit value. Put zero if you do not wish to use intensity threshold.");
			Dialog.addNumber("threshold of Intensity (lower limit)", thresholdInt);
			Dialog.addCheckbox("ROI（解析対象チャネルのROG値で選抜後）を保存する", saveRogRoi);
			Dialog.addMessage("\nEnter Intensity range of preview image.");
			Dialog.addNumber("preview image range min", intRangeMin);
			Dialog.addNumber("preview image range max", intRangeMax);
			Dialog.addCheckbox("Skip dialog and use the same settings.", skipdialog_exportrog);
			Dialog.show();
			thresholdRog = Dialog.getNumber();
			thresholdInt = Dialog.getNumber();
			saveRogRoi = Dialog.getCheckbox();
			intRangeMin = Dialog.getNumber();
			intRangeMax = Dialog.getNumber();			
			skipdialog_exportrog = Dialog.getCheckbox();
			exportRogPrevParameters_new[0] = thresholdRog;
			exportRogPrevParameters_new[1] = thresholdInt;
			exportRogPrevParameters_new[2] = saveRogRoi;
			exportRogPrevParameters_new[6] = skipdialog_exportrog;
			exportRogPrevParameters_new[7] = intRangeMin;
			exportRogPrevParameters_new[8] = intRangeMax;	
		}

		setMinAndMax(intRangeMin, intRangeMax);
		
		for(i=0;i<nRows;i++){
			x = Table.get("roiCenterX", i);
			y = Table.get("roiCenterY", i);
			intensity = Table.get("meanLuminance", i);
			if(CALCULATE_ROG){ //240920 no ROG calculation allowed
				rog = Table.get("ROG", i);
				if(rog < thresholdRog && intensity > thresholdInt){
					makeRectangle(x-8, y-8, 16, 16);
					roiManager("add");
				}				
			} else {
				if(intensity > thresholdInt){
					makeRectangle(x-8, y-8, 16, 16);
					roiManager("add");
				}				
			}
		}
		if(skipdialog_exportrog == false){
			waitForUser("Adjust & check image contrast.");
			getMinAndMax(intRangeMin, intRangeMax); 
		}
		roiManager("deselect"); //24o920 deselect added
		run("Flatten");
		setColor(255,255,255);
		if(CALCULATE_ROG){ //240920 no ROG calculation allowed
			labeltext = imgIdentifier +  "_ROG(" + thresholdRog + ")";
		}
		if(thresholdInt != 0){
			labeltext = labeltext + "_Int(" + thresholdInt + ")";
		}
		labeltext = replace(labeltext,"\\.","_");
		print(labeltext);
		run("Label...", "format=Text starting=0 interval=1 x=5 y=" + (height -5) + " font=20 text=" + labeltext + " range=1-1");
		saveAs("PNG", workDir + File.separator + labeltext + ".png");	
		
		//waitForUser("start save rog roi");
		if(saveRogRoi){ //220114追加。ROGで限定したあとのROIの書き出し。
			selectWindow("rogpreview");
			roiManager("reset");

			roiCentersTableTitle = "RoiCenters";
			selectWindow(tableName);

			for(i=0;i<nRows;i++){
				x = Table.get("roiCenterX", i);
				y = Table.get("roiCenterY", i);
				rog = Table.get("ROG", i);
				intensity = Table.get("meanLuminance", i);
				if(rog < thresholdRog && intensity > thresholdInt){
					makeOval(x-roiDiameter/2, y-roiDiameter/2, roiDiameter, roiDiameter);
					roiManager("add");
				}
			}
			if(roiManager("count")>0){
				roiManager("save", workDir + File.separator + labeltext + "ROI.zip");
			} else {
				f = File.open(workDir + File.separator + labeltext + "ROI.txt");
				print(f, "This is a dummy file when no ROI met the condition.");
				File.close(f); //ただのcloseになっていたので修正 230309
			}
			close("rogpreview");//230306 rogpreviewが複数チャネル解析の時残ってしまっていたせいで、ROI .zipは無事だが.pngの画像が間違っている場合がある。
		}
	}
	return exportRogPrevParameters_new;
}

/**
 * 211012追加、各輝点位置の16x16 crop画像のROGを計算する。
 * roiCentersTableTitle,  "RoiCenters", "MeanLuminaces", 
 */
 function measureRog(imgTitle, channelIdx) {
	cropsizeRog = 16;

	selectWindow(imgTitle);
	Stack.setPosition(channelIdx, 1, 1);
	getDimensions(_, _, _, _, nFrames);

	roiCentersTableTitle = "RoiCenters";
	selectWindow(roiCentersTableTitle);
	roiCxCoords = Table.getColumn("X");
	roiCyCoords = Table.getColumn("Y");
	nRois = Table.size;

	//setBatchMode("hide");


	if (nFrames == 1) {
		rogResultTableTitle = "MeanLuminances";
		for (roiIdx=0; roiIdx<nRois; roiIdx++) {

			if(roiIdx - floor(roiIdx/2000) * 2000 == 0){
				print("current roiIdx: " + roiIdx);
				Table.update;
				selectWindow(imgTitle);
				selectWindow(rogResultTableTitle);
				//waitForUser;
			}
			
			makeRectangle(roiCxCoords[roiIdx] - cropsizeRog / 2, roiCyCoords[roiIdx] - cropsizeRog / 2, cropsizeRog, cropsizeRog);	
			rog = selectionRog();
			Table.set("ROG", roiIdx, rog);
			//Table.setColumn("test", roiCxCoords);
			
			
		}
		Table.update;
	} else {
		
		rogResultTableTitle = "ROGs";
		Table.create(rogResultTableTitle);
		selectWindow(rogResultTableTitle);
		selectWindow(imgTitle);
		for (frameIdx=1; frameIdx<=nFrames; frameIdx++) {
			Stack.setFrame(frameIdx);
			for (roiIdx=0; roiIdx<nRois; roiIdx++) {
				if(roiIdx - floor(roiIdx/2000) * 2000 == 0){
					print("current roiIdx: " + roiIdx);
					Table.update;
					selectWindow(imgTitle);
					selectWindow(rogResultTableTitle);
					//waitForUser;
				}
				makeRectangle(roiCxCoords[roiIdx] - cropsizeRog / 2, roiCyCoords[roiIdx] - cropsizeRog / 2, cropsizeRog, cropsizeRog);	
				rog = selectionRog();
				Table.set(roiIdx, frameIdx-1, rog);
			}
		}
		Table.update;
		saveResult(rogResultTableTitle, WORK_DIR, imgIdentifier+'_ROG.csv');
	}

	
	return rogResultTableTitle;
}




/**
 * imgTitle, channelIdxで指定される画像を使用してROIの輝度値の測定を行い、
 * 結果を記録したテーブルのウィンドウタイトルを返却する
 * @param  imgTitle   測定対象の画像のタイトル
 * @param  channelIdx 測定対象のチャネル番号（1はじまり）
 * @return            結果を記録したテーブルのウィンドウタイトル
 */
function measure(imgTitle, channelIdx) {
	selectWindow(imgTitle);
	Stack.setPosition(channelIdx, 1, 1);

	getDimensions(_, _, _, _, nFrames);
	print("start measurement...");

	run("Set Measurements...", "mean centroid");

	resultTableTitle = "MeanLuminances";
	Table.create(resultTableTitle);

	if (nFrames == 1) {
		//時間が一次元の場合
		roiManager("multi-measure");
		selectWindow("Results");
		meanLuminances = Table.getColumn("Mean");
		roiCxCoords = Table.getColumn("X");
		roiCyCoords = Table.getColumn("Y");
		Table.reset("Results");

		//meanLuminancesテーブル以下のカラムを追加
		//- meanLuminance: ROIの平均輝度
		//- roiCenterX: ROIの中心x座標
		//- roiCenterY: ROIの中心y座標
		selectWindow(resultTableTitle);
		Table.setColumn("meanLuminance", meanLuminances);
		Table.setColumn("roiCenterX", roiCxCoords);
		Table.setColumn("roiCenterY", roiCyCoords);

	} else {
		//時間軸があるデータの場合
		for (frameIdx=1; frameIdx<=nFrames; frameIdx++) {
			selectWindow(imgTitle); //210526追加
			Stack.setFrame(frameIdx);
			roiManager("multi-measure");

			selectWindow("Results");
			nRois = Table.size;
			meanLuminances = Table.getColumn("Mean");
			waitForUser("Now multi-measure");

			Table.reset("Results");

			selectWindow(resultTableTitle);
			Table.update; //220518追加。これがないとフレームが多い時に途中で止まることがある？？
			
			for (roiIdx=0; roiIdx<nRois; roiIdx++) {
				Table.set(roiIdx, frameIdx-1, meanLuminances[roiIdx]);
			}
		}
	}

	if(CALCULATE_ROG){
		measureRog(imgTitle, channelIdx);
	}
	//220114~ 外部からROIを読み込んだ場合、読み込んだROIのファイル名をcsvに記録するように変更
	if(LOAD_ROI){
		selectWindow(resultTableTitle);
		infos = newArray(Table.size);
		for(i=0;i<lengthOf(infos);i++){
			infos[i] = "_";
		}
		infos[1] = "roifile="+roiFilename;
		Table.setColumn("AnalysisInfo", infos);
		//waitForUser;

	}
	return resultTableTitle;
}

/**
 * resultTableTitleの内容をcsvファイルとして保存する
 * @param  resultTableTitle 保存するテーブルのウィンドウタイトル
 * @param  workDir          結果出力先ディレクトリ
 * @param  filename         保存するファイル名
 */
function saveResult(resultTableTitle, workDir, filename) {
	selectWindow(resultTableTitle);

	headings = Table.headings;
	headingsArray = split(headings, "\t");

	Table.saveColumnHeader(false); //ヘッダーの保存なし
	saveAs("results", workDir + File.separator + filename); //results: テーブル形式でデータ保存

	Table.rename(filename, resultTableTitle); //テーブルのタイトルをもとにもどす

}

/**
 * ウィンドウ、Roi manager、選択状態をリセットする
 * @param  exceptions 閉じないウィンドウタイトルの配列
 */
function terminateExcept(exceptions) {
	//Roi managerリセット
	roiManager("reset");

	//選択を全て解除
	run("Select None");

	//exceptionsに含まれるタイトル以外の画像を閉じる
	imgTitles = getList("image.titles");
	for (i=0; i<lengthOf(imgTitles); i++) {
		if (arrayContains(exceptions, imgTitles[i])) {
			continue;
		}
		close(imgTitles[i]);
	}

	//exceptionsに含まれるタイトル以外のウィンドウを閉じる
	noImgWindowTitles = getList("window.titles");
	for (i=0; i<lengthOf(noImgWindowTitles); i++) {
		if (arrayContains(exceptions, noImgWindowTitles[i])) {
			continue;
		}
		close(noImgWindowTitles[i]);
	}
}

/**
 * ROIを表示した画像をスタックとして一つにまとめる
 * ROI表示画像のウィンドウタイトル: roi_{imgIdentifier}
 */
function stackRoiImages() {
	options = newArray(
		"name=Stack",
		"title=roi_",
		"use"
	);
	run("Images to Stack", String.join(options, " "));
}

/**
 * 呼び出された時点のタイムスタンプを返却する
 * @param  format "yyyy-MM-dd HH:mm:ss" or "yyMMddHHmm"で指定
 * @return        timestamp
 */
function getTimestamp(format) {
	months = newArray("01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12");

	getDateAndTime(year, monthIdx, dayOfWeek, dayOfMonth, hour, minute, second, msec);

	if (format == "yyyy-MM-dd HH:mm:ss") {
		timestamp = "" + year + "-" + months[monthIdx] + "-" + IJ.pad(dayOfMonth, 2) + " " + IJ.pad(hour, 2) + ":" + IJ.pad(minute, 2) + ":" + IJ.pad(second, 2);
	} else if (format == "yyMMddHHmm") {
		timestamp = substring(year, 2) + months[monthIdx] + IJ.pad(dayOfMonth, 2)+ IJ.pad(hour, 2) + IJ.pad(minute, 2);
	}

	return timestamp;
}

/**
 * ファイルの絶対/相対パスから拡張子を抽出して返却する
 * @param  path ファイルの絶対/相対パス
 * @return      extension
 */
function getFileExtension(path) {
	fileName = File.getName(path);
	fileNameElements = split(fileName, ".");
	//.で区切られた末尾の要素を拡張子とする
	extension = fileNameElements[lengthOf(fileNameElements)-1];

	return extension;
}

/**
 * 配列arrにvalueが含まれる場合はtrue, 含まれない場合はfalseを返却する
 * @param  arr   検証対象の配列
 * @param  value 検索する文字列
 * @return       boolean
 */
function arrayContains(arr, value) {
	for (i=0; i<lengthOf(arr); i++) {
		if (arr[i] == value) {
			return true;
		}
	}

	return false;
}

function saveLog(path, filename){
	f=File.open(path + File.separator + filename);
	print(f, "WORK_DIR" + "\t" + WORK_DIR + "\n");
	print(f, "START_FIELD_IDX" + "\t" + START_FIELD_IDX + "\n");
	print(f, "END_FIELD_IDX" + "\t" + END_FIELD_IDX + "\n");
	print(f, "fieldIDX" + "\t" + fieldIdx + "\n");
	print(f, "ROI_CHANNEL_IDX" + "\t" + ROI_CHANNEL_IDX + "\n");
	print(f, "ANALYSIS_CHANNEL_IDX" + "\t" + ANALYSIS_CHANNEL_IDX + "\n");
	print(f, "imgIdentifier" + "\t" + imgIdentifier + "\n");
	print(f, "CORRECT_DRIFT" + "\t" + CORRECT_DRIFT + "\n");
	print(f, "LOAD_ROI" + "\t" + LOAD_ROI + "\n");
	if(LOAD_ROI){
		print(f, "ROI_DIR" + "\t" + ROI_DIR +  "\n"); 
		print(f, "roiFilename" + "\t" + roiFilename +  "\n"); 
	}
	print(f, "ANALYSIS_CHANNE_WTH" + "\t" + ANALYSIS_CHANNEL_WTH + "\n");
	print(f, "CALCULATE_ROG" + "\t" + CALCULATE_ROG + "\n");
	print(f, "EXPORT_POSITIVES" + "\t" + EXPORT_POSITIVES + "\n");
	print(f, "SCREENREGION" + "\t" + SCREENREGION + "\n");
	print(f, "BEADSELISA" + "\t" + BEADSELISA + "\n");
	print(f, "DUALCOLOR" + "\t" + DUALCOLOR + "\n");
	if(DUALCOLOR){
		print(f, "ANALYSIS_CHANNELS_ARRAY" + "\t" + "{" + String.join(ANALYSIS_CHANNELS_ARRAY + ",") + "}" +  "\n"); 
	}
	print(f, "SHOW_ROI" + "\t" + SHOW_ROI + "\n");
	print(f, "SAVE_ROI" + "\t" + SAVE_ROI + "\n");
	print(f, "WTH_RADIUS" + "\t" + WTH_RADIUS + "\n");
	print(f, "prom" + "\t" + detectRoiParameters[0] + "\n");
	print(f, "roichblur" + "\t" + detectRoiParameters[2] + "\n");
	print(f, "roiradius" + "\t" + detectRoiParameters[4] + "\n");
	print(f, "beads_channelBF" + "\t" + detectRoiParameters[5] + "\n");
	print(f, "beads_areamin" + "\t" + detectRoiParameters[6] + "\n");
	print(f, "beads_areamax" + "\t" + detectRoiParameters[7] + "\n");
	print(f, "beads_tolerance" + "\t" + detectRoiParameters[8] + "\n");
	print(f, "beads_invertedanalysis" + "\t" + detectRoiParameters[9] + "\n");
	print(f, "beads_BTHradius" + "\t" + detectRoiParameters[10] + "\n");
	print(f, "beads_closingradius" + "\t" + detectRoiParameters[11] + "\n");
	print(f, "beads_thresholdmethod" + "\t" + detectRoiParameters[12] + "\n");
	print(f, "fov_presence_roi" + "\t" + detectRoiParameters[13] + "\n");
	print(f, "screenregion_use_erosion" + "\t" + detectRoiParameters[14] + "\n"); 
	print(f, "screenregion_erosion_radius" + "\t" + detectRoiParameters[15] + "\n"); 
	print(f, "screenregion_roich_lower" + "\t" + detectRoiParameters[16] + "\n"); 
	print(f, "screenregion_roich_upper" + "\t" + detectRoiParameters[17] + "\n"); 
	if(EXPORT_POSITIVES){
		if(DUALCOLOR){
			print(f, "1st-thresRogUL" + "\t" + exportRogPrevParameters[0] + "\n");
			print(f, "1st-thresIntLL" + "\t" + exportRogPrevParameters[1] + "\n");
			print(f, "1st-saveRogRoi" + "\t" + exportRogPrevParameters[2] + "\n");
			print(f, "2nd-thresRogUL" + "\t" + exportRogPrevParameters[3] + "\n");
			print(f, "2nd-thresIntLL" + "\t" + exportRogPrevParameters[4] + "\n");
			print(f, "2nd-saveRogRoi" + "\t" + exportRogPrevParameters[5] + "\n");	
		} else {
			print(f, "thresRogUL" + "\t" + exportRogPrevParameters[0] + "\n");
			print(f, "thresIntLL" + "\t" + exportRogPrevParameters[1] + "\n");
			print(f, "saveRogRoi" + "\t" + exportRogPrevParameters[2] + "\n");			
		}		
	}
	File.close(f);
}



//要求バージョン確認
requires("1.53d");

//パラメータ設定
#@ File (label="解析結果出力先ディレクトリ", style="directory") WORK_DIR
#@ File (label="解析対象画像", style="file") ORIGINAL_IMG_PATH
#@ Integer (label="解析開始視野番号（1はじまり）", discription="解析対象視野の開始番号（1はじまり）を入力してください。") START_FIELD_IDX
#@ Integer (label="解析終了視野番号（1はじまり）", discription="解析対象視野の終了番号（1はじまり）を入力してください。") END_FIELD_IDX
#@ Integer (label="ROI設定チャネル番号（1はじまり）", discription="ROIの設定に使用するチャネル番号（1はじまり）を入力してください。") ROI_CHANNEL_IDX
#@ Integer (label="解析チャネル番号（1はじまり）", discription="解析に使用するチャネル番号（1はじまり）を入力してください。") ANALYSIS_CHANNEL_IDX
#@ Boolean (label="ドリフト補正を行う", value=false, discription="時間経過による視野のズレ補正を行います。") CORRECT_DRIFT
#@ Boolean (label="ROIファイルを使用してROIを設定する", value=false, discription="事前に準備したROIファイルを使用してROIを設定します。") LOAD_ROI
#@ Boolean (label="★Median, Mean, White Top Hatしてから輝度解析", value=false, discription="バックグラウンド軽減処理をしてから輝度解析する場合") ANALYSIS_CHANNEL_WTH
#@ Boolean (label="★ROG値の算出を行う", value=false, discription="輝点ごとのROG値（8x8切り出し）をcsv形式で書き出す") CALCULATE_ROG //240920 EXPORT_ROGの機能をCALCULATE_ROGとEXPORT_POSITIVESに分割
#@ Boolean (label="★陽性判定輝点の書き出しを行う", value=false, discription="陽性判定輝点の書き出し") EXPORT_POSITIVES //240920 EXPORT_ROGの機能をCALCULATE_ROGとEXPORT_POSITIVESに分割
#@ String (label="★解析範囲の設定", choices={"全画面解析", "中央円形領域解析", "輝度値範囲指定","マニュアル領域設定"},　value="中央円形領域解析", style="radioButtonHorizontal") SCREENREGION
//#@ Boolean (label="★全画面解析", value=false, discription="チェック時でも端8pxは除外される。チェックしない場合は中央円形ROI内のみを解析") FULLSCREEN
#@ Boolean (label="ビーズELISA解析", value=false, discription="明視野でビーズのあるチャンバーのみを解析する") BEADSELISA
#@ Boolean (label="解析チャネルが２つある", value=false, discription="Dual color イメージングの場合など。ROIの保存にチェック必須です。") DUALCOLOR
//スクリプト使用時の留意事項
#@ String (visibility=MESSAGE, value="<html><br/>※ 以下の場合は追加プラグインのインストールが必要です。詳しくはマニュアルをご確認ください。<ul><li>VSIファイルを読み込む場合</li><li>ドリフト補正機能を使用する場合</li></ul></html>") _

//条件分岐の必要なパラメータの設定
if (DUALCOLOR) {
	//二色の波長を一度に解析する場合 230214
	Dialog.create("解析チャネルが二つある場合の設定");
	ANALYSIS_CHANNELS_ARRAY = newArray(ANALYSIS_CHANNEL_IDX, ANALYSIS_CHANNEL_IDX);
	Dialog.addNumber("解析チャネル１", ANALYSIS_CHANNELS_ARRAY[0]);
	Dialog.addNumber("解析チャネル２", ANALYSIS_CHANNELS_ARRAY[1]);
	Dialog.show();
	ANALYSIS_CHANNELS_ARRAY[0] = Dialog.getNumber();
	ANALYSIS_CHANNELS_ARRAY[1] = Dialog.getNumber();
}

if (LOAD_ROI) {
	//事前準備したROIファイルを使用してROIを設定する場合
	Dialog.create("ROIファイル読み込み設定");
	Dialog.addDirectory("ROIファイル読み込み元ディレクトリ", WORK_DIR);
	Dialog.show();
	ROI_DIR = Dialog.getString();
	//ROI表示をON, ROI保存をOFFに設定
	SHOW_ROI = true;
	SAVE_ROI = false;
} else {
	//ROIをこの解析で設定する場合			"open=\'"+imgPath + "\'", //added quotations, 211004
	Dialog.create("ROI表示・保存設定");
	Dialog.addCheckbox("ROIを表示する", true);
	Dialog.addCheckbox("ROI（ROIチャネルのlocal maximum基準）を保存する", true);
	Dialog.show();
	SHOW_ROI = Dialog.getCheckbox();
	SAVE_ROI = Dialog.getCheckbox();
}

WTH_RADIUS = -1;
if(ANALYSIS_CHANNEL_WTH){
	Dialog.create("White Top Hat設定");
	Dialog.addMessage("median 半径1px, mean 半径1px, White Top Hat (Square) の順で処理をしてから計測します");
	Dialog.addNumber("White Top Hat処理の半径 (px)", 50);		
	Dialog.show();
	WTH_RADIUS = Dialog.getNumber();	
}


//detectRoiParameters: 0prom, 1maximaok, 2roichblur, 3roicenterstabletitle, 4roiRadius, 
// (continued) 5findbeads-channelBFnum, 6findbeads-minarea, 7findbeads-maxarea, 8findbeads-tolerance, 9findbeads-doinvertedanalysis, 10findbeads-BTHradius, 11beads_closingradius, 12beads_thresholdmethod
// (continued)  13fov_roiPresence, 14screenregion_use_erosion, 15screenregion_erosion_radius, 16screenregion_roich_lower, 17screenregion_roich_upper, 18skipdialog_screenregion, 19skipdialog_findmaxima, 20skipdialog_roiradius 240201
detectRoiParameters_default = newArray(100, false, "No", "Untitled", -1,  1, 2, 100, 0, 0,  6, 3, "Otsu", "", true, 10, 0,  2000, false, false, false);



//exportRogPrevParameters  0thresRogUL, 1thresIntLL, 2saveRogRoi, 3_2ndch-thresRogUL, 4_2ndch-thresIntLL, 5_2ndch-saveRogRoi, 6skipdialog_exportrog, 7intRangeMin, 9intRangeMax, 240920 
exportRogPrevParameters_default = newArray(5.5, 0, true, 5.5, 0, true, false, 0, 2000);

//findBeadsParameters: channelBFnumber, minarea, maxarea, tolerance. 230309
//findBeadsParameters = newArray(1, 0, 100, 0);


print("[" + getTimestamp("yyyy-MM-dd HH:mm:ss") + "] Analysis start.");

main();

print("[" + getTimestamp("yyyy-MM-dd HH:mm:ss") + "] Analysis completed.");

//2409201230の前のバージョンは2402071230を使用した。240809のバージョンはいくつか古い仕様の部分があった（バージョン管理が間違っていた？）たｍ。