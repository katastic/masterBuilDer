module app;
import utility;

import std.process, std.path, std.stdio;
import std.format, std.file;
import toml;
import std.parallelism;
import std.string : indexOf, indexOfAny, lastIndexOf, replace, toLower, strip;
import std.algorithm : map;
import std.array : array;
import std.conv : to;

/// Scan for files in source directories, and compare differences with stored TOML hashes.
final class FileCacheList{	
	import std.digest.crc;
	string dir;
	fileHashes database;
	fileHashes differencesDb;
	bool foundDifferences = false;
	string[] tempFiles;

	this(string[] filenames){
		tempFiles = filenames;
		differencesDb = compareAndFindDifferences();
		if(differencesDb.length > 0){
			verboseWriteln("Found differences:", differencesDb);
			foundDifferences = true;
			}
		}
		
	string[] getDifferences() => differencesDb.keys;

	fileHashes compareAndFindDifferences(){
		fileHashes oldValues 	 = scanCachedHashes();
		fileHashes currentValues = scanHashes(tempFiles);
		if(oldValues.length == 0){ verboseWriteln("No cached data. Enumerating all files."); return currentValues;}
		database = currentValues; // NOTE: SIDE-EFFECT. Calling this updates our perception of database.
		fileHashes differences;

		foreach(k,v; oldValues){    verboseWritefln("old    %s %s", k, v);}
		foreach(k,v; currentValues){verboseWritefln("cached %s %s", k, v);}

		// what if a file is REMOVED??
		verboseWriteln("compareAndFindDifferences() - DIFFERENCES");
		foreach(k, v; currentValues){
			if(k !in oldValues){
				verboseWritefln("\t%30s - %s [NEW]", k, v);
				differences[k] = v;
				continue;
				}
			if(currentValues[k] != oldValues[k]){				
				verboseWritefln("\t%30s - %s vs %s [DIFF]", k, v, oldValues[k]);
				differences[k] = v;
				} else {
				verboseWritefln("\t%30s - %s vs %s [MATCH]", k, v, currentValues[k]);
				}
			}

		// HOW do we detect if the NEW FILE has finished correctly with new files?
		// easiest: only update when compile succeeds.
		// otherwise, store and track executable CRC too?

		// we also want to rebuild EACH FILE to a temp object at some point.
		// and also support CLEAN for cleaning them up
		return differences;
		}
	
	void saveResults(){
		writeNewCachedList(database);
		}

	void writeNewCachedList(fileHashes db){	
		auto file = File(exeConfig.cacheFileName, "w");
		file.writeln("[fileHashes]");

		verboseWriteln("OUTPUT TO FILE--> ", exeConfig.cacheFileName);
		foreach(f, hex; db){
			//string hex = toHexString!(LetterCase.lower)(digest!CRC32(readText(f))).dup;
			verboseWritefln("\t%30s - %s", f, hex);
			file.writefln("\"%s\" = \"%s\"", f, hex);
			database[f] = hex;
			}
		}

	// TODO: specify alternate build file support in exeConfig or something.
	fileHashes scanCachedHashes(){
		fileHashes results;
		try{
			TOMLDocument doc2 = parseTOML(cast(string)read(exeConfig.cacheFileName));
			verboseWriteln("scanCachedHashes() - ", exeConfig.cacheFileName);
			foreach(f, hex; doc2["fileHashes"]){
				verboseWritefln("\t%30s - %s", f, hex.str);
				results[f] = hex.str;
				}
		}catch(Exception e){
			writefln("No %s file found, or inaccessable.", exeConfig.cacheFileName); 
			}
		return results;
		}

	fileHashes scanHashes(string[] files){
		fileHashes results;
		verboseWriteln("scanHashes() - FileCacheList:");
		foreach(f; files){
			string hex = toHexString!(LetterCase.lower)(digest!CRC32(readText(f))).dup;
			verboseWritefln("\t%30s - %s", f, hex);
			results[f] = hex;
			}
		return results;
		}
	}

struct ModeStringConfig{
	string[string] modePerCompiler; 
	}

struct GlobalConfiguration{	 /// settings that apply to all profiles
	ModeStringConfig[string] modeStrings;
	string[string] dScannerStrings;
	string[] dScannerSelectedStrings;

	// [Options]
	bool automaticallyAddOutputExtension = true;  /// leaves it as 'main' for linux, changes to 'main.exe' for windows.
	// do we need this with various profiles setting output file name?
	}

/// TODO: Confirm all dir paths always end with a slash so we don't have any accidental combinations
/// where we have to add the slash to add the filename on the end.
struct FilePath{
	string filename; 		/// myfile.exe
	string extension; 		/// .exe
	string basename;		/// myfile
	string reldir;			///	./bin/
	string absdir;			/// C:/git/taco/bin/
	string relpathAndName; 	/// ./bin/myfile.exe
	string fullPathAndName;	/// C:/git/taco/bin/myfile.exe

	this(string _fullPathAndName){ // how do we handle if we gave it a directory? These are all FILES right?
		fullPathAndName = _fullPathAndName;		
		computeData();
		}
	
	this(DirEntry d){
		fullPathAndName = d.name;
		computeData();
		}

	void computeData(){
		alias fp = fullPathAndName;
		// what if we have multiple dots or dots in the directory names?! We need the LAST one.
		// and it has to occur _after_ any slashes. [also slashes must be OS specific]
		// need either nested slashes function or regex

		string delimeter = "ERROR";
		version(Windows){delimeter = "\\";}
		version(linux){delimeter = "/";}
		assert(delimeter != "ERROR");

		// what if we have NO SLASHES. just a raw name? (well then it's not absolute)
//		if(!fp.isAny("\\")){
		
		string delim = "\\";
		version(linux)delim = "/";

		if(fp.isAnyAfter(".", delim)){
			auto idx = fp.lastIndexOf(".");
			if(idx != -1){
				extension = fp[idx+1..$]; // filename.d -> 'd'

				auto j = fp.lastIndexOf(delim);
				if(j != -1){ // filename.d -> 'filename'
					basename = fp[j+1..idx];  
					absdir = fp[0..j];
					}else{
					basename = fp[0..idx];
					absdir = "";
					}

				filename = format("%s.%s", basename, extension); // 'filename.d'
				}else{
				}
			verboseWritefln("FilePath() - string [%32s] basename[%12s], extension[%3s] filename[%14s] absdir[%s]",
				 fp, basename, extension, filename, absdir);
			}else{
			extension = "";
			writefln("FilePath() - No file extension found for string [%s]", fp);
			}
		}
	}

/// Target data: windows, linux, etc
struct TargetConfiguration{
	string target;
	string compilerName;
	
	string[] sourcePaths;
	string[] recursiveSourcePaths;
	string[] libPaths;
	string[] recursiveLibPaths;
	string[] libs;

	string[] includePaths;   /// where to find dependency source files (but NOT compile them)
	string intermediatePath; /// where intermediate binary files go

	// enumerated data
	string[] sourceFilesFound;
	FilePath[] sourceFilesFound2;
	}

struct ProfileConfiguration{ /// "release", "debug", special stuff like "scanme" (a user script)
	string mode; /// full mode string ala "-d -debug -o" should this be normal pieces?
	string[] modesEnabled;
	string outputFilename = "main"; // automatically adds .exe
	}

// Should we be separating runToml into profile vs global scans?
ProfileConfiguration[string] runToml(){
	import toml;
	TOMLDocument doc;

	verboseWriteln(readText(exeConfig.buildScriptFileName));
	doc = parseTOML(cast(string)read(exeConfig.buildScriptFileName));
	
	auto compilers = doc["project"]["compilers"].array;
	foreach(c; compilers)verboseWriteln("compilers found: ", c);
	
	auto targets = doc["project"]["targets"].array;
	foreach(t; targets)verboseWriteln("targets found: ", t);
	
	foreach(k, v; doc["dscannerStrings"]){
		globalConfig.dScannerStrings[k] = v.str;
		}
	globalConfig.dScannerSelectedStrings = convTOMLtoArray(doc["dscanner"]["hide"]);

	template wrapInException(string path){ //fixme bad name. Also. Not used anymore???
    	const char[] wrapInException = format("
			{
				try{
					// how do we put our own code in here without quotation marks? A run a delegate?
					%s
					}
				}catch(Exception e){
					writeln(\"Exception occured: \", e);
				}
			}", path);
		}
	verboseWriteln();

	globalConfig.automaticallyAddOutputExtension = doc["options"]["automaticallyAddOutputExtension"].boolean;

	string[] compilerNames = convTOMLtoArray(doc["project"]["compilers"]);
	foreach(m, n; doc["modeStrings"]){
		verboseWriteln("[",m, "] = ", n[0], "/", n[1], " of type ", n.type); // string. note: hardcoded with number of compilers
		ModeStringConfig _modeString;
		foreach(i, t; n.array){_modeString.modePerCompiler[compilerNames[i]] ~= t.str;}
		globalConfig.modeStrings[m] = _modeString;
		}
	verboseWriteln(globalConfig);	

	foreach(t; targets){
		TargetConfiguration tc;
		verboseWriteln("doc", t.str);
		auto d = doc[t.str];
		tc.target = t.str;

	//	foreach(value; d["sourcePaths"].array){cc.sourcePaths ~= value.str;}
		tc.sourcePaths 			= convTOMLtoArray(d["sourcePaths"]);
		tc.recursiveSourcePaths = convTOMLtoArray(d["recursiveSourcePaths"]);
		tc.libPaths 			= convTOMLtoArray(d["libPaths"]); 
		tc.recursiveLibPaths 	= convTOMLtoArray(d["recursiveLibPaths"]);
		tc.libs 				= convTOMLtoArray(d["libs"]);

		tc.includePaths 		= convTOMLtoArray(d["includePaths"]);
		tc.intermediatePath 	= d["intermediatePath"].str;

		foreach(path; tc.sourcePaths){
				verboseWritefln("try scanning path %s for target %s", path, tc.target);
				try{				
					version(windows)if(tc.target != "windows")continue;
					version(linux)if(tc.target != "linux")continue;
					foreach(DirEntry de; dirEntries(path, "*.d", SpanMode.shallow)){
						if(de.isHidden)
						verboseWriteln("\t", de);
						tc.sourceFilesFound ~= de.name;
						tc.sourceFilesFound2 ~= FilePath(de);
						}
				}catch(Exception e){
					writeln("Exception occured: ", e);
				}
			}
		tConfigs[t.str] = tc;		
		verboseWriteln("Source files found: ", tc.sourceFilesFound2.map!"a.filename");
		}
	
	ProfileConfiguration[string] pConfigs;
	foreach(mode; doc["project"]["profiles"].array){
		string name = mode.str;
		verboseWritefln("Reading profile: ", name); // "debug", "release", etc
		auto buildProfileData = doc[mode.str];
		verboseWriteln("\t", buildProfileData);
		ProfileConfiguration pc;
		auto modeArray = buildProfileData["modesEnabled"].array; // selected modes for configuration
		pc.modesEnabled = convTOMLtoArray(buildProfileData["modesEnabled"]);
		string temp;
		string currentCompiler = "dmd"; // TODO FIXME.  compilerNames[i]?
		foreach(i, m; modeArray){
			verboseWriteln(i, m);
			verboseWritefln("\tfound mode ", m.str);
			temp ~= globalConfig.modeStrings[m.str].modePerCompiler[currentCompiler] ~ " ";
			}
		pc.mode = temp;
		verboseWritefln("\tfull mode string [%s]", temp);		
		pConfigs[name] = pc;
		}
	return pConfigs;
	}

/// Try to parse a TOML doc value, and if not, dump error without interrupting other attempts.
/// Might need a global didErrorOccur so program can at least notice them.
void tryParse(T, U)(ref T output, U val){
		try{
		output = val;
		}catch(Exception e){
		writefln("Couldn't find or parse value [%s]", e);
		}
	}

/// Configuration options for the executable itself such as paths to tools. Options that may not
/// copy over from one installation to the next.
class ExeConfigType{
	TOMLDocument doc;

	this(){
		this("");
		}

	this(string filepath){
		// verboseWritefln("reading TOML file for exeConfig [%s]", filepath);
		// CANT use verbosewriteln, it needs THIS setup.
		try{
			string newPath = filepath ~ "mbConfig.toml";
			writeln("Using config file at", newPath);
			string data = cast(string)read(newPath);//r"C:\git\masterBuilDer\mbConfig.toml");
			doc = parseTOML(data);
		}catch(Exception e){
			writefln("No mbConfig file found or readable [searched for %s]. Resorting to default exe configuration.", filepath);
		}
		if(doc !is null){
			parseStuff(doc);
			}else{
			//useDefaults(); // should already be set with inits.
			}
		}

	final void parseStuff(TOMLDocument doc){
		tryParse(colorizeOutput, doc["options"]["colorizeOutput"].boolean);
		//colorizeOutput 			= doc["options"]["colorizeOutput"].boolean;
		
		useExternalHighlighter 	= doc["options"]["useExternalHighlighter"].boolean;
		dscannerLoc 			= doc["externalLocations"]["dscanner"].str;
		pygmentizeLoc 			= doc["externalLocations"]["pygmentize"].str;
		auto pygmentizeLoc2 	= doc["externalLocations"]["pygmentize"].str; // test
		assert(pygmentizeLoc == pygmentizeLoc2);
		}

	bool colorizeOutput = false;
	bool useExternalHighlighter = false;
	string dscannerLoc="";
	string pygmentizeLoc="";

	bool forwardRemainingArguments 	= false;
	string forwardArguments 		= "";

	bool doPrintVerbose 			= false; /// for error troubleshooting
	bool doParallelCompile	  		= true;
	bool doCachedCompile 			= true;
	bool doRunCompiler 				= false;
	bool didCompileSucceed 			= false;
	string modeSet					="default"; // todo: change to enum or whatever. /// This is the builder mode state variable! NOT a "mode"/profile/etc. 'default' to start.
	
	string selectedProfile 	= "release";
	string selectedCompiler = "dmd";
	string selectedTargetOS = "windows";  // set by version statement in main.

	string buildScriptFileName 	= "buildConfig.toml"; /// Unless overriden with option TODO
	string cacheFileName 		= "buildFileCache.toml"; // should this be in the buildConfig?
	string extraCompilerFlags 	= "";
	string extraLinkerFlags 	= "";
	}

/// Display help prompt
void displayHelp(){
	writeln("");
	writeln("  masterBuilder[.exe] [command] [option=value] [option=value] -- args");
	writeln("");
	writeln("\tinit  - create a default build config. TODO.");
	writeln("\trun   - run the program");
	writeln("\tbuild - actually build");
	writeln("\tclean - clean up temporary files");
	writeln("\tcheck - check if any files have changed and list them.");
	writeln("\ttry   - see if the build config would produce a compiler command");
	writeln("\tlint  - run DScanner");
	writeln("\tquote - recieve a verse about the Master Builder");
	writeln("\thelp  - this help screen.");
	writeln("");
	writeln("\tOptions:");
	writeln("\t\tprofile=name/of/profile (profile=release, profile=debug, etc)");
	writeln("\t\ttarget=windows/linux (Use commands for a different OS. Default: Your host OS.)");
	writeln("\t\tcompilerflags=\"taco is a bad man\" (use shell quotes for strings with spaces) ");
	writeln("\t\tlinkerflags=--test                  (quotes not required if no spaces)");
	writeln("");
	writeln("\tFor passing commandline arguments to the program, use -- to end");
	writeln("\t  internal processing of args and send them to the program.");
	writeln("");
	writeln("\tExample usage:");
	writeln("");
	writeln("\t masterBuilder build profile=debug -- hello!");
	writeln("\t  - build profile named debug, run, and pass it \"hello!\" ");
	}

/// Display a quote
void displayQuote(){
	import quotes, std.random;
	writeln();
	writefln("\"%s\"", quoteStrings[ uniform!"[]"(0, cast(int)quoteStrings.length-1)] );
	writeln();
	}

/// Run dscanner pass
void runLint(){
	import std.typecons : Yes;
	import std.algorithm.iteration : filter, splitter;
	import std.array : split;
	import std.string;
	import std.algorithm.searching : canFind;
	import std.algorithm.iteration : each;
	import toml;
	// TODO	
	runToml();
	//TOMLDocument doc = parseTOML(cast(string)read(buildConfig.toml));

	auto targetOS = exeConfig.selectedTargetOS;
	string filesList;
	// FIX: we need to run the PARSE TOML to get source file locations first!
	foreach(file; tConfigs[targetOS].sourceFilesFound2){ // similar to commandBuild
		filesList ~= file.fullPathAndName ~ " ";	
		}
	string runString = format("%s -S %s", exeConfig.dscannerLoc, filesList); 
	writeln("Running:", runString);
	auto dscan = executeShell(runString);
	if (dscan.status != 0){
		string[] output = dscan.output.splitter("\n").array;
		string[] output2;
		foreach(line; output)
			{
			foreach(match; globalConfig.dScannerSelectedStrings){
				//writeln("searching for ", match);
				// EXCEPTION if matches aren't in array, we should check in the runToml fufnction.
				if(line.canFind(globalConfig.dScannerStrings[match]))goto end;
				} // if we don't match anything, let the line through.
			output2 ~= line;
			end:
			}
		auto output3 = output2.join("\n");
		writeln("dscanner lint errors:\n", output3);
		}else{		
		writeln("dscanner succeeded:\n", dscan.output);
		}
	}

/// Return: -1 on error
int parseModeInit(string arg){
	verboseWritefln("parseModeInit(%s)", arg);
	switch(arg.strip){
		case "build": exeConfig.doRunCompiler = true ; exeConfig.modeSet = "build"; return 0;
		case "try"  : exeConfig.doRunCompiler = false; exeConfig.modeSet = "build"; return 0;
		case "quote": displayQuote(); return 0;
		case "lint" : runLint(); return 0;
		case "help" : case "man": displayHelp(); return 0;
		default     : displayHelp();return 0;
		}
//	terminateEarlyString(arg);	
//	return -1;
	}

/// Return: -1 on error
int parseModeBuild(string arg){
	verboseWritefln("parseModeBuild(%s)", arg);	
	immutable long n = arg.indexOfAny("=");

	if(arg == "--"){
		verboseWritefln("Forward argument mode detected!");
		exeConfig.forwardRemainingArguments = true;
		return 0;
		}

	if(n == -1){writeln("Error. Option missing equals?"); terminateEarlyString(arg); return -1;} // args must be in key=value, so if there's no equal it's invalid.
	verboseWritefln("matching [%s] = [%s]", arg[0..n], arg[n+1..$]);
	immutable string option = arg[0..n];
	immutable string value  = arg[n+1..$].strip;
	// note we ONLY change case of option! We don't want to
	//  accidentally change case of a compiler flag string!
	switch(option.toLower){
		case "config":
			verboseWritefln("Setting config=%s config files path", value);			
			auto exeConfigOld = exeConfig;
			exeConfig = new ExeConfigType(value);
			writeln("NEW CONFIG:", exeConfig);
			// take run-time set old values:
			exeConfig.doRunCompiler = exeConfigOld.doRunCompiler;
			exeConfig.modeSet = exeConfigOld.modeSet;
			
			// set new path
			exeConfig.buildScriptFileName = value~"buildConfig.toml";
			exeConfig.cacheFileName = value~"buildFileCache.toml"; // better place/way to do this? Also dir separator
			exeConfig.doRunCompiler = true ; 
			exeConfig.modeSet = "build";
			return 0;
		case "cached":
			verboseWritefln("Setting cached=%s", value.toLower);
			auto val = value.toLower;
			if     (val == "true"  || val == "yes" || val == "on" ){writeln(" * Cached mode on"); exeConfig.doCachedCompile = true; return 0;}
			else if(val == "false" || val == "no"  || val == "off"){writeln(" * Cached mode off"); exeConfig.doCachedCompile = false; return 0;}
			else { writefln("Unrecognized option: [%s]", val);}
		return -1;
		case "parallel":
			verboseWritefln("Setting parallel=%s", value.toLower);
			auto val = value.toLower;
			if     (val == "true"  || val == "yes" || val == "on" ){writeln(" * Parallel mode on"); exeConfig.doParallelCompile = true; return 0;}
			else if(val == "false" || val == "no"  || val == "off"){writeln(" * Parallel mode off"); exeConfig.doParallelCompile = false; return 0;}
			else { writefln("Unrecognized option: [%s]", val);}
		return -1;
		case "verbose":
			verboseWritefln("Setting verbose=%s", value.toLower);
			auto val = value.toLower;
			if     (val == "true"  || val == "yes" || val == "on" ){writeln(" * Verbose mode on"); exeConfig.doPrintVerbose = true; return 0;}
			else if(val == "false" || val == "no"  || val == "off"){writeln(" * Verbose mode off"); exeConfig.doPrintVerbose = false; return 0;}
			else { writefln("Unrecognized option: [%s]", val);}
		return -1;
		case "profile":
			verboseWriteln("Setting profile=", value.toLower);
			exeConfig.selectedProfile = value.toLower;
			// look for profile names? We need to scan profiles before this?
			// or just let it rangeException out later.
		return 0;
		case "target":
			verboseWriteln("Setting target=", value.toLower);
			exeConfig.selectedTargetOS = value.toLower;
		return 0;
		case "compiler":
			verboseWriteln("Setting compiler=", value.toLower);
			exeConfig.selectedCompiler = value.toLower;
		return 0;
		case "compilerflags":
			verboseWriteln("Setting compilerflags=", value);
			if(value.isAny(" "))
				exeConfig.extraCompilerFlags = "\"" ~ value ~ "\""; // [myString stuff] becomes ["myString stuff"]
				 // .replace("\"", "\\\"")  but how do we handle embedded strings? What does OS send? Maybe already good enough.
			else
				exeConfig.extraCompilerFlags = value;
		return 0;
		case "linkerflags":
			verboseWriteln("Setting linkerflags=", value);
			if(value.isAny(" "))
				exeConfig.extraLinkerFlags = "\"" ~ value ~ "\""; // [myString stuff] becomes ["myString stuff"]
				 // .replace("\"", "\\\"")  but how do we handle embedded strings? What does OS send? Maybe already good enough.
			else
				exeConfig.extraLinkerFlags = value;
		return 0;
		default:
		terminateEarlyString(arg);
		return -1;
		}
	}

void setForwardArguments(string arg){
	exeConfig.forwardArguments ~= arg ~ " ";
	}

void terminateEarlyString(string arg){
	writeln("Unrecognized command: ", arg);
	displayHelp();
	}

void parseCommandline(string[] myArgs){
	verboseWriteln("args:", myArgs);
	with(exeConfig){
		foreach(arg; myArgs){
				if(forwardRemainingArguments){setForwardArguments(arg);}
				else{
					if(modeSet=="default"){if(parseModeInit(arg)){return;}}
					else if(modeSet=="build" || modeSet=="go"){if(parseModeBuild(arg)){return;}}
					else if(modeSet=="helper"){displayHelp();}
					else if(modeSet=="quote"){displayQuote();}
					else if(modeSet=="run"){commandRun();}
				}
			}
		if(modeSet == "build" || modeSet == "go")commandBuild();
		if(modeSet == "go" && didCompileSucceed)commandRun(); // "go" = build and run
		}
	return;
	}

void commandRun(){
	// exeConfig.forwardArguments
	}

void commandClean(){
	// - delete intermediate directory
	// - delete executable
	} // TODO FIX ME BUG

void commandBuild(){
	ProfileConfiguration[string]  pConfigs = runToml();
	verboseWriteln(pConfigs);
	version(Windows)string binaryExtension = ".obj";
	version(linux)string binaryExtension = ".o";
    string filesList = "";
    string filesObjList = "";
	auto targetOS = exeConfig.selectedTargetOS;
	auto profile = exeConfig.selectedProfile;
	auto compiler = exeConfig.selectedCompiler;
	verboseWriteln("");
	displayQuote();
	verboseWriteln("");
    verboseWriteln("Files to compile [", targetOS,"]");
	foreach(t; tConfigs)verboseWriteln(t.sourceFilesFound);
	foreach(file; tConfigs[targetOS].sourceFilesFound2){
		filesList ~= file.fullPathAndName ~ " "; //file ~ " ";
		filesObjList ~= tConfigs[targetOS].intermediatePath ~ file.filename.replace(".d",binaryExtension) ~ " ";
		}
	verboseWriteln("filesObjList - ", filesObjList);
	verboseWritefln("Files List \"%s\"\n", filesList);
	auto fcl = new FileCacheList(tConfigs[targetOS].sourceFilesFound);
	string[] changedFiles = fcl.getDifferences();
	writeln("Changed files detected:");
	foreach(f; changedFiles)writeln("\t", f);
	writeln();
    verboseWriteln("Library paths:");
	string libPathList = "";
	foreach(libpath; tConfigs[targetOS].libPaths){
		switch(tConfigs[targetOS].target){
			case("linux"):   libPathList ~= "-L-L"~libpath~" "; 		break;
			case("windows"): libPathList ~= "-L/LIBPATH:"~libpath~" ";	break;
			case("macosx") : assert(0, "macosx not tested");
			default:		 assert(0, format("invalid target name [%s]", profile));
			}
		}
	verboseWritefln("\t\"%s\"", libPathList);
	verboseWriteln("");
	writefln("Buildname: %s (%s/%s)", profile, targetOS, compiler);
	writeln("");

    immutable string flags = pConfigs[profile].mode;
	string runString;
	bool doCachedCompile=true;
	
	string fileExtension;
	if(exeConfig.selectedTargetOS == "windows"){
		fileExtension=".exe";
		}else{
		fileExtension="";
		}

	if(!doCachedCompile){
		runString =
			"dmd -of=" ~ pConfigs[profile].outputFilename~fileExtension ~ 
		  	" " ~ flags ~ " " ~ 	pConfigs[exeConfig.selectedProfile].mode ~ " "~	filesList ~ " " ~ libPathList ~ " " ~ 
			exeConfig.extraCompilerFlags ~ " " ~ exeConfig.extraLinkerFlags;
		
		if(exeConfig.doRunCompiler){
		auto dmd = executeShell(runString);
		if (dmd.status != 0){
			writeln("Compilation failed:\n", dmd.output);
			}else{
			writefln("Writing to [%s]", pConfigs[profile].outputFilename~fileExtension);
			writeln("Compilation succeeded:\n\n", dmd.output);
			writeln();
			exeConfig.didCompileSucceed = true;
			fcl.saveResults();
			}
		}else{
		writeln("Would have tried to execute the following string:");
		writeln("\t",runString);
		}
	}else{		
		writeln("Attempting incremental compile.\n");
		
		bool stopOnFirstError = true; /// do we stop on the first errored compile, or attempt all? exeConfig option?
		bool hasErrorOccurred = false; 
		if(exeConfig.doParallelCompile == false){
			writeln(" - single-threaded mode:");
			foreach(file; changedFiles){

			string includePathsStr;
			foreach(p; tConfigs[targetOS].includePaths)
				includePathsStr ~= format("-I%s ", p);

				string execString = format("dmd -c %s %s -od=%s %s %s", 
					includePathsStr, 
					pConfigs[exeConfig.selectedProfile].mode,
					tConfigs[targetOS].intermediatePath,					
					file,
					libPathList); //-od doesn't seem to even do anything
				
				if(exeConfig.doRunCompiler){
					verboseWriteln("trying to execute:\t", execString);
					auto exec = executeShell(execString);				
					if(exec.status != 0){
						writefln("Compilation of %s failed:\n%s", file, exec.output);
						if(stopOnFirstError)break;
						}else{
						writefln("Compilation of %s succeeded.", file);
						}
					}else{
					writeln("Would have tried to execute (file to obj):\n\n\t", execString);
					}
				}

			if(hasErrorOccurred){writeln("Individual file compilation failed."); return;}
		}else{
		writeln(" - multi threaded mode");
		// TODO ?
		// Also, if we need a dependency graph of build order, we could figure one
		// out either automatically (just keep compiling random ones until the order works), or allow manual.

		// we might want to store each ones stdout/stderr and display them sequentually so there's no
		// stdout race conditions, and also only display stderr of those that fail.

		try{
		foreach(immutable file; taskPool.parallel(changedFiles)){
			immutable FilePath filepath = FilePath(file);
			string fileStr = tConfigs[targetOS].intermediatePath ~ filepath.basename ~ binaryExtension;
			string includePathsStr;
			foreach(p; tConfigs[targetOS].includePaths)
				includePathsStr ~= format("-I%s ", p);

			string execString = format("dmd -c %s -od=%s %s %s %s -of=%s",   // does -od even work??
				includePathsStr,
				tConfigs[targetOS].intermediatePath,
				pConfigs[exeConfig.selectedProfile].mode,
				file,
				libPathList, 
				fileStr); 
							
			if(exeConfig.doRunCompiler){
				verboseWriteln("trying to execute:\n\t", execString);
				auto exec = executeShell(execString);				
				if(exec.status != 0){
						writefln("Compilation of %s failed:\n%s", file, exec.output);
						//if(stopOnFirstError)break; // can't do breaks in parallel foreach
						}else{
						writefln("Compilation of %s succeeded.", file);
						}
					}else{
					writeln("Would have tried to execute (file to obj):\n\t", execString);
					}
				}
			}catch(Exception e){
			writeln(e);
			assert(false);
			}

		if(hasErrorOccurred){writeln("Individual file compilation failed."); return;}
		}
		
		// then if they all succeed, compile the final product.
		runString = "dmd -of=" ~ pConfigs[profile].outputFilename~fileExtension ~ 
		  	" " ~ flags ~ " " ~	
			filesObjList.replace(
					tConfigs[targetOS].sourcePaths[0],
					tConfigs[targetOS].intermediatePath) ~ " " ~ 
			libPathList ~ " " ~ exeConfig.extraCompilerFlags ~ " " ~ exeConfig.extraLinkerFlags;

		if(!exeConfig.doRunCompiler){
			writeln();
			writeln("Would have tried to execute (executable):\n\t", runString);
			}else{
			writeln("Trying to execute:\n\t", runString);
			auto dmd = executeShell(runString);				
			if(dmd.status != 0){
				writeln();
				writefln("Compilation failed:\n\n%s", dmd.output);
				}else{
				writefln("Compilation succeeded.\n");
				}
			}
		}
	}

// __gshared because taskpool.parallel is too stupid to have access to these with TLS.
__gshared GlobalConfiguration globalConfig;
__gshared TargetConfiguration[string] tConfigs;
__gshared ExeConfigType exeConfig;

void setup(){	
	exeConfig = new ExeConfigType("");
	setVerboseModeVariable(&exeConfig.doPrintVerbose); 
	setupDefaultOSstring();
	}

void setupDefaultOSstring(){
	exeConfig.selectedTargetOS = "excuse me, wat"; // default fail case.
	version(Windows)exeConfig.selectedTargetOS = "windows";
	version(linux)exeConfig.selectedTargetOS   = "linux";
	version(MacOSX)exeConfig.selectedTargetOS  = "macosx";
	}

int main(string[] args){
	setup();
	if(args.length > 1){
		writefln("masterBuilder %s", args[1..$]);
		parseCommandline(args[1..$]);
		}else{
		writefln("masterBuilder");
		displayHelp();
		}
    return 0;
	}
