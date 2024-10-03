/+
	TEST is cached build is actually working or rebuilding always.
		+ was missing for multithread compile
		- still test more.

	- ALSO, we're still compiling executable even if ALL source files have NO updates!



	we can compile dub packages by going into dir and running dub 


	-> we need "go" command or whatever. compile and run if successful.

	+  why aren't we outputing main.exe (windows) to the output directory????
		of=main.exe !!!

		we probably want a projectRootPath, and then an output path if different!

		DETECT if root or relative? Or set a config? for all other paths

	- we can set the working directory of executeShell! Maybe set it to our root directory? The config directory?
	
	- TODO: instead of mb [try/build] it should just build by default, and if you add try, it does try.
		- any peculilarities with our variable system?  (mb.exe try verbose=yes)

	- TODO: Many variables probably need exposed. color=yes/no/auto
		- Is there a way to cross-platform detect terminal width, and color support?
			- we might need ncurses, etc for that which I would want shimmed to another file and also I like keeping the deps as minimal as possible.
				- there is a dub ncurses lib
					https://code.dlang.org/packages/ncurses

	- TODO: Fix/add relative paths!

	- TODO: We need to understand/allow understanding static vs dynamic linking of libraries such as Allegro. It could be as simple as writing another profile in the toml, such as release-static and release-dynamic.

	- TODO FUN: Implement pre/post script functionality. Do we run a separate script on fail, or send PASS/FAIL as an argument to the script? Either might be fine. And where best to store these scripts? We can do ./scripts/build/triggers. Not sure if we need /build/ for anything else but people may think you're supposed to use them manually if they're in /build.
		or just /scripts/triggers 

	- ERROR: Multi compile continues even if one fails. It might only be if the COMPILE fails but without a source code error (a link/import failure)

	we need to add a LINT check for the absurd stupidty that is version strings
		version(Windows)   	uppercase!
		version(linux) 		lowercase!
		version(windows)	NO ERROR. silently does nothing.
		version(Linux)		NO ERROR. silently does nothing.

	- verboseWriteln is wrong. it adds newlines for each element.

	- BUG, pragma(msg, "using dmd version of allegro") is just output multiple times and spammed into a single text buffer. maybe it's STDERR.

------------
	+ BUG on command line colorizing. FIXED.
	+ TODO: use mb.exe instead of masterbuilder[.exe]
+/

module app;
import utility;
import help;

import std.process, std.path, std.stdio;
import std.format, std.file;
import std.parallelism;
import std.string : indexOf, indexOfAny, lastIndexOf, replace, toLower, strip;
import std.algorithm : map;
import std.array : array;
import std.conv : to;
import toml;

/// Scan for files in source directories, and compare differences with stored TOML hashes.
final class FileCacheList {
	import std.digest.crc;

	string dir;
	fileHashes database;
	fileHashes differencesDb;
	bool foundDifferences = false;
	string[] tempFiles;

	this(string[] filenames) {
		tempFiles = filenames;
		differencesDb = compareAndFindDifferences();
		if (differencesDb.length > 0) {
			verboseWriteln("Found differences:", differencesDb);
			foundDifferences = true;
		}
	}

	string[] getDifferences() => differencesDb.keys;

	fileHashes compareAndFindDifferences() {
		fileHashes oldValues = scanCachedHashes();
		fileHashes currentValues = scanHashes(tempFiles);
		if (oldValues.length == 0) {
			verboseWriteln("No cached data. Enumerating all files.");
			return currentValues;
		}
		database = currentValues; // NOTE: SIDE-EFFECT. Calling this updates our perception of database.
		fileHashes differences;

		foreach (k, v; oldValues) {
			verboseWritefln("old    %s %s", k, v);
		}
		foreach (k, v; currentValues) {
			verboseWritefln("cached %s %s", k, v);
		}

		// what if a file is REMOVED??
		verboseWriteln("compareAndFindDifferences() - DIFFERENCES");
		foreach (k, v; currentValues) {
			if (k !in oldValues) {
				verboseWritefln("\t%30s - %s [NEW]", k, v);
				differences[k] = v;
				continue;
			}
			if (currentValues[k] != oldValues[k]) {
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

	void saveResults() {
		writeNewCachedList(database);
	}

	void writeNewCachedList(fileHashes db) {
		auto file = File(exeConfig.cacheFileName, "w");
		file.writeln("[fileHashes]");

		verboseWriteln("OUTPUT TO FILE--> ", exeConfig.cacheFileName);
		foreach (f, hex; db) {
			//string hex = toHexString!(LetterCase.lower)(digest!CRC32(readText(f))).dup;
			verboseWritefln("\t%30s - %s", f, hex);
			file.writefln("\"%s\" = \"%s\"", f, hex);
			database[f] = hex;
		}
	}

	fileHashes scanCachedHashes() {
		fileHashes results;
		try {
			TOMLDocument doc2 = parseTOML(cast(string) read(exeConfig.cacheFileName));
			verboseWriteln("scanCachedHashes() - ", exeConfig.cacheFileName);
			foreach (f, hex; doc2["fileHashes"]) {
				verboseWritefln("\t%30s - %s", f, hex.str);
				results[f] = hex.str;
			}
		} catch (Exception e) {
			writefln("No %s file found, or inaccessable.", exeConfig.cacheFileName);
		}
		return results;
	}

	fileHashes scanHashes(string[] files) {
		fileHashes results;
		verboseWriteln("scanHashes() - FileCacheList:");
		foreach (f; files) {
			string hex = toHexString!(LetterCase.lower)(digest!CRC32(readText(f))).dup;
			verboseWritefln("\t%30s - %s", f, hex);
			results[f] = hex;
		}
		return results;
	}
}

struct ModeStringConfig {
	string[string] modePerCompiler;
}

struct GlobalConfiguration { /// settings that apply to all profiles
	ModeStringConfig[string] modeStrings;
	string[string] dScannerStrings;
	string[] dScannerSelectedStrings;

	// [Options]
	bool automaticallyAddOutputExtension = true; /// leaves it as 'main' for linux, changes to 'main.exe' for windows.
	// do we need this with various profiles setting output file name?
}

/// TODO: Confirm all dir paths always end with a slash so we don't have any accidental combinations
/// where we have to add the slash to add the filename on the end.
struct FilePath {
	string filename; /// myfile.exe
	string extension; /// .exe
	string basename; /// myfile
	string reldir; ///	./bin/
	string absdir; /// C:/git/taco/bin/
	string relpathAndName; /// ./bin/myfile.exe
	string fullPathAndName; /// C:/git/taco/bin/myfile.exe

	this(string _fullPathAndName) { // how do we handle if we gave it a directory? These are all FILES right?
		fullPathAndName = _fullPathAndName;
		computeData();
	}

	this(DirEntry d) {
		fullPathAndName = d.name;
		computeData();
	}

	void computeData() {
		alias fp = fullPathAndName;
		// what if we have multiple dots or dots in the directory names?! We need the LAST one.
		// and it has to occur _after_ any slashes. [also slashes must be OS specific]
		// need either nested slashes function or regex

		string delimeter = "ERROR";
		version (Windows) {
			delimeter = "\\";
		}
		version (linux) {
			delimeter = "/";
		}
		assert(delimeter != "ERROR");

		// what if we have NO SLASHES. just a raw name? (well then it's not absolute)
		//		if(!fp.isAny("\\")){

		string delim = "\\";
		version (linux)
			delim = "/";

		if (fp.isAnyAfter(".", delim)) {
			auto idx = fp.lastIndexOf(".");
			if (idx != -1) {
				extension = fp[idx + 1 .. $]; // filename.d -> 'd'

				auto j = fp.lastIndexOf(delim);
				if (j != -1) { // filename.d -> 'filename'
					basename = fp[j + 1 .. idx];
					absdir = fp[0 .. j];
				} else {
					basename = fp[0 .. idx];
					absdir = "";
				}

				filename = format("%s.%s", basename, extension); // 'filename.d'
			} else {
			}
			verboseWritefln("FilePath() - string [%32s] basename[%12s], extension[%3s] filename[%14s] absdir[%s]",
				fp, basename, extension, filename, absdir);
		} else {
			extension = "";
			writefln("FilePath() - No file extension found for string [%s]", fp);
		}
	}
}

/// Target data: windows, linux, etc
struct TargetConfiguration {
	string target;
	string compilerName;

	string[] sourcePaths;
	string[] recursiveSourcePaths;
	string[] libPaths;
	string[] recursiveLibPaths;
	string[] libs;

	string[] includePaths; /// where to find dependency source files (but NOT compile them)
	string intermediatePath; /// where intermediate binary files go

	string outputPath;
	string projectRootPath;

	// enumerated data
	string[] sourceFilesFound;
	FilePath[] sourceFilesFound2;
}

struct ProfileConfiguration { /// "release", "debug", special stuff like "scanme" (a user script)
	string mode; /// full mode string ala "-d -debug -o" should this be normal pieces?
	string[] modesEnabled;
	string outputFilename = "main"; // automatically adds .exe
}

// Should we be separating runToml into profile vs global scans?
ProfileConfiguration[string] runToml() {
	import toml;

	TOMLDocument doc;

	//exeConfig parsing
	//------------------------------------------------------------------------------------
	verboseWriteln(readText(exeConfig.buildScriptFileName));
	doc = parseTOML(cast(string) read(exeConfig.buildScriptFileName));

	auto compilers = doc["project"]["compilers"].array;
	foreach (c; compilers)
		verboseWriteln("compilers found: ", c);

	auto targets = doc["project"]["targets"].array;
	foreach (t; targets)
		verboseWriteln("targets found: ", t);

	foreach (k, v; doc["dscannerStrings"]) {
		globalConfig.dScannerStrings[k] = v.str;
	}
	globalConfig.dScannerSelectedStrings = convTOMLtoArray(doc["dscanner"]["hide"]);

	template wrapInException(string path) { //fixme bad name. Also. Not used anymore???
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

	globalConfig.automaticallyAddOutputExtension = doc["options"]["automaticallyAddOutputExtension"]
		.boolean;
	exeConfig.runProgramAfterward = doc["options"]["runProgramAfterward"].boolean;

	string[] compilerNames = convTOMLtoArray(doc["project"]["compilers"]);
	foreach (m, n; doc["modeStrings"]) {
		//	verboseWrite("[",m, "] = ", n[0], "/", n[1], " of type ", n.type); // string. note: hardcoded with number of compilers
		ModeStringConfig _modeString;
		foreach (i, t; n.array) {
			_modeString.modePerCompiler[compilerNames[i]] ~= t.str;
		}
		globalConfig.modeStrings[m] = _modeString;
	}
	verboseWriteln(globalConfig);

	auto OS = exeConfig.selectedTargetOS;

	foreach (t; targets) {
		TargetConfiguration tc;
		verboseWriteln("doc", t.str);
		auto d = doc[t.str];
		tc.target = t.str;

		//	foreach(value; d["sourcePaths"].array){cc.sourcePaths ~= value.str;}
		tc.sourcePaths = convTOMLtoArray(d["sourcePaths"]);
		tc.recursiveSourcePaths = convTOMLtoArray(d["recursiveSourcePaths"]);
		tc.libPaths = convTOMLtoArray(d["libPaths"]);
		tc.recursiveLibPaths = convTOMLtoArray(d["recursiveLibPaths"]);
		tc.libs = convTOMLtoArray(d["libs"]);

		tc.includePaths = convTOMLtoArray(d["includePaths"]);
		tc.intermediatePath = d["intermediatePath"].str;

		tc.outputPath = d["outputPath"].str;
		tc.projectRootPath = d["projectRootPath"].str;

		//writeln("tc.target: ", tc.target);
		foreach (path; tc.sourcePaths) {
			version (Windows)
				if (tc.target != "windows") {
					verboseWriteln("skip non-windows config file scanning.");
					continue;
				}
			version (linux)
				if (tc.target != "linux") {
					verboseWriteln("skip non-linux config file scanning.");
					continue;
				}
			verboseWritefln("try scanning path %s for target %s", path, tc.target);
			try {

				foreach (DirEntry de; dirEntries(path, "*.d", SpanMode.shallow)) {
					if (de.isHidden)
						verboseWriteln("\t", de);
					tc.sourceFilesFound ~= de.name;
					tc.sourceFilesFound2 ~= FilePath(de);
				}
			} catch (Exception e) {
				writeln("Exception occured: ", e);
			}
		}
		tConfigs[t.str] = tc;
		verboseWriteln("Source files found: ", tc.sourceFilesFound2.map!"a.filename");
	}

	ProfileConfiguration[string] pConfigs;
	foreach (mode; doc["project"]["profiles"].array) {
		string name = mode.str;
		verboseWritefln("Reading profile: ", name); // "debug", "release", etc
		auto buildProfileData = doc[mode.str];
		verboseWriteln("\t", buildProfileData);
		ProfileConfiguration pc;
		auto modeArray = buildProfileData["modesEnabled"].array; // selected modes for configuration
		pc.modesEnabled = convTOMLtoArray(buildProfileData["modesEnabled"]);
		string temp;
		string currentCompiler = "dmd"; // TODO FIXME.  compilerNames[i]?
		foreach (i, m; modeArray) {
			//verboseWriteln(i, m);
			//verboseWritefln("\tfound mode ", m.str);
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
void tryParse(T, U)(ref T output, U val) {
	try {
		output = val;
	} catch (Exception e) {
		writefln("Couldn't find or parse value [%s]", e);
	}
}

/// Configuration options for the executable itself such as paths to tools. Options that may not
/// copy over from one installation to the next.
class ExeConfigType {
	TOMLDocument doc;

	this() {
		this("");
	}

	this(string filepath) {
		// verboseWritefln("reading TOML file for exeConfig [%s]", filepath);
		// CANT use verbosewriteln, it needs THIS setup.
		try {
			string newPath = filepath ~ "mbConfig.toml";
			writeln("Using config file at [", newPath, "]");
			string data = cast(string) read(newPath); //r"C:\git\masterBuilDer\mbConfig.toml");
			doc = parseTOML(data);
		} catch (Exception e) {
			writefln("No mbConfig file found or readable [searched for %s]. Resorting to default exe configuration.", filepath);
		}
		if (doc !is null) {
			parseStuff(doc);
		} else {
			//useDefaults(); // should already be set with inits.
		}
	}

	final void parseStuff(TOMLDocument doc) {
		tryParse(colorizeOutput, doc["options"]["colorizeOutput"].boolean);
		//colorizeOutput 			= doc["options"]["colorizeOutput"].boolean;

		useExternalHighlighter = doc["options"]["useExternalHighlighter"].boolean;
		dscannerLoc = doc["externalLocations"]["dscanner"].str;
		pygmentizeLoc = doc["externalLocations"]["pygmentize"].str;
		auto pygmentizeLoc2 = doc["externalLocations"]["pygmentize"].str; // test
		assert(pygmentizeLoc == pygmentizeLoc2);
	}

	bool makeBellOnError = true;
	bool colorizeOutput = false;
	bool useExternalHighlighter = false;
	string dscannerLoc = "";
	string pygmentizeLoc = "";

	bool forwardRemainingArguments = false;
	string forwardArguments = "";

	bool doPrintVerbose = false; /// for error troubleshooting
	bool doParallelCompile = true;
	bool doCachedCompile = true;
	bool doRunCompiler = false;
	bool didCompileSucceed = false;
	bool runProgramAfterward = true;
	string modeSet = "default"; // todo: change to enum or whatever. /// This is the builder mode state variable! NOT a "mode"/profile/etc. 'default' to start.

	string selectedProfile = "debug"; /// default profile: debug symbols.
	string selectedCompiler = "dmd";
	string selectedTargetOS = "SETME"; // set by version statement in main.

	string buildScriptFileName = "buildConfig.toml"; /// Unless overriden with option TODO
	string cacheFileName = "buildFileCache.toml"; // should this be in the buildConfig?
	string extraCompilerFlags = "";
	string extraLinkerFlags = "";
}

/// Display a quote
void displayQuote() {
	import quotes, std.random;

	int quoteNumber = uniform!"[]"(0, cast(int) quoteStrings.length - 1);
	writeln();
	writefln("\"%s\"", quoteStrings[quoteNumber].wordWrap(80)); // we don't know the terminal width though. More effort than worth to cross-platform that. So use 80.
	writeln();
}

/// Run dscanner pass
void runLint() {
	import std.typecons : Yes;
	import std.algorithm.iteration : filter, splitter;
	import std.array : split;
	import std.string;
	import std.algorithm.searching : canFind;
	import std.algorithm.iteration : each;
	import toml;

	// TODO	FIX
	auto discardedValue = runToml();
	//TOMLDocument doc = parseTOML(cast(string)read(buildConfig.toml));

	auto targetOS = exeConfig.selectedTargetOS;
	string filesList;
	// FIX: we need to run the PARSE TOML to get source file locations first!
	foreach (file; tConfigs[targetOS].sourceFilesFound2) { // similar to commandBuild
		filesList ~= file.fullPathAndName ~ " ";
	}
	string runString = format("%s -S %s", exeConfig.dscannerLoc, filesList);
	writeln("Running:", runString);
	auto dscan = executeShell(runString);
	if (dscan.status != 0) {
		string[] output = dscan.output.splitter("\n").array;
		string[] output2;
		foreach (line; output) {
			foreach (match; globalConfig.dScannerSelectedStrings) {
				//writeln("searching for ", match);
				// EXCEPTION if matches aren't in array, we should check in the runToml fufnction.
				if (line.canFind(globalConfig.dScannerStrings[match]))
					goto end;
			} // if we don't match anything, let the line through.
			output2 ~= line;
		end:
		}
		auto output3 = output2.join("\n");
		writeln("dscanner lint errors:\n", output3);
	} else {
		writeln("dscanner succeeded:\n", dscan.output);
	}
}

/// Return: -1 on error
int parseModeInit(string arg) {
	verboseWritefln("parseModeInit(%s)", arg);
	switch (arg.strip) {
	case "run":
		writeln("we set modeSet = run");
		exeConfig.modeSet = "run";
		exeConfig.didCompileSucceed = true; // encapsulation break? needed?
		return 0;
	case "build":
		exeConfig.doRunCompiler = true;
		exeConfig.modeSet = "build";
		return 0;
	case "try":
		exeConfig.doRunCompiler = false;
		exeConfig.modeSet = "build";
		return 0;
	case "quote":
		displayQuote();
		return 0;
	case "lint":
		runLint();
		return 0;
	case "help":
	case "man":
		displayHelp();
		return 0;
	default:
		displayHelp();
		return 0;
	}
	//	terminateEarlyString(arg);	
	//	return -1;
}

/// Return: -1 on error
int parseModeBuild(string arg) {
	verboseWritefln("parseModeBuild(%s)", arg);
	immutable long n = arg.indexOfAny("=");

	if (arg == "--") {
		verboseWritefln("Forward argument mode detected!");
		exeConfig.forwardRemainingArguments = true;
		return 0;
	}

	if (n == -1) {
		writeln("Error. Option missing equals?");
		terminateEarlyString(arg);
		return -1;
	} // args must be in key=value, so if there's no equal it's invalid.
	verboseWritefln("matching [%s] = [%s]", arg[0 .. n], arg[n + 1 .. $]);
	immutable string option = arg[0 .. n];
	immutable string value = arg[n + 1 .. $].strip;
	// note we ONLY change case of option! We don't want to
	//  accidentally change case of a compiler flag string!
	switch (option.toLower) {
	case "config":
		verboseWritefln("Setting config=%s config files path", value);
		auto exeConfigOld = exeConfig;
		exeConfig = new ExeConfigType(value);
		writeln("NEW CONFIG:", exeConfig);
		// take run-time set old values:
		exeConfig.doRunCompiler = exeConfigOld.doRunCompiler;
		exeConfig.modeSet = exeConfigOld.modeSet;

		// set new path
		exeConfig.buildScriptFileName = value ~ "buildConfig.toml";
		exeConfig.cacheFileName = value ~ "buildFileCache.toml"; // better place/way to do this? Also dir separator
		exeConfig.doRunCompiler = true;
		exeConfig.modeSet = "build";
		return 0;
	case "cached":
		verboseWritefln("Setting cached=%s", value.toLower);
		auto val = value.toLower;
		if (val == "true" || val == "yes" || val == "on") {
			writeln(" * Cached mode on");
			exeConfig.doCachedCompile = true;
			return 0;
		} else if (val == "false" || val == "no" || val == "off") {
			writeln(" * Cached mode off");
			exeConfig.doCachedCompile = false;
			return 0;
		} else {
			writefln("Unrecognized option: [%s]", val);
		}
		return -1;
	case "parallel":
		verboseWritefln("Setting parallel=%s", value.toLower);
		auto val = value.toLower;
		if (val == "true" || val == "yes" || val == "on") {
			writeln(" * Parallel mode on");
			exeConfig.doParallelCompile = true;
			return 0;
		} else if (val == "false" || val == "no" || val == "off") {
			writeln(" * Parallel mode off");
			exeConfig.doParallelCompile = false;
			return 0;
		} else {
			writefln("Unrecognized option: [%s]", val);
		}
		return -1;
	case "verbose":
		verboseWritefln("Setting verbose=%s", value.toLower);
		auto val = value.toLower;
		if (val == "true" || val == "yes" || val == "on") {
			writeln(" * Verbose mode on");
			exeConfig.doPrintVerbose = true;
			return 0;
		} else if (val == "false" || val == "no" || val == "off") {
			writeln(" * Verbose mode off");
			exeConfig.doPrintVerbose = false;
			return 0;
		} else {
			writefln("Unrecognized option: [%s]", val);
		}
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
		if (value.isAny(" "))
			exeConfig.extraCompilerFlags = "\"" ~ value ~ "\""; // [myString stuff] becomes ["myString stuff"]
		// .replace("\"", "\\\"")  but how do we handle embedded strings? What does OS send? Maybe already good enough.
		else
			exeConfig.extraCompilerFlags = value;
		return 0;
	case "linkerflags":
		verboseWriteln("Setting linkerflags=", value);
		if (value.isAny(" "))
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

void setForwardArguments(string arg) {
	exeConfig.forwardArguments ~= arg ~ " ";
}

void terminateEarlyString(string arg) {
	writeln("Unrecognized command: ", arg);
	displayHelp();
}

void parseCommandline(string[] myArgs) {
	verboseWriteln("args:", myArgs);
	with (exeConfig) {
		foreach (arg; myArgs) {
			if (forwardRemainingArguments) {
				setForwardArguments(arg);
					writeln("forward");
			} else { // <---------------- This looks INCREDIBLY WRONG.
				writeln("else: [", arg,"], vs modeSet[", modeSet,"]");
				if (modeSet == "default") { 
					writeln("NOTICED NOTHING");
					if (parseModeInit(arg))return;
					writeln("modeset now:", modeSet);
				} else if (modeSet == "build" || modeSet == "go") {
					writeln("NOTICED BUILD/GO");
					if (parseModeBuild(arg)) {
						return;
					}
				} else if (modeSet == "helper") {//<-------
					writeln("NOTICED HELPER"); 
					displayHelp();
				} else if (modeSet == "quote") { //<-------
					writeln("NOTICED QUOTE");
					displayQuote();
				} else if (modeSet == "run") { //<-------
					writeln("NOTICED RUN");
					commandRun();
				}
			}
			writeln("arg was ", arg);
		}
		
		if (modeSet == "build" || modeSet == "go")
			commandBuild();
		if (modeSet == "run" || (modeSet == "go" && didCompileSucceed))
			commandRun(); // "go" = build and run
	}
	return;
}

void commandRun() {
	writeln("commandRun()");
	auto pConfigs2 = runToml();
	string fileExtension;
	if (exeConfig.selectedTargetOS == "windows")
		fileExtension = ".exe"; 
	else 
		fileExtension = "";
	auto profile = exeConfig.selectedProfile;
	string filename = pConfigs2[profile].outputFilename ~ fileExtension;
	string outputFileStr = tConfigs[exeConfig.selectedTargetOS].projectRootPath ~ filename;
	runProgram(outputFileStr, exeConfig.selectedTargetOS);
	// exeConfig.forwardArguments
}

void commandClean() {
	// - delete intermediate directory
	// - delete executable
} // TODO FIX ME BUG

string redBold = "\x1b[1;31m";
string greenBold = "\x1b[0;32m"; // DOESNT WORK in win terminal
string greenBold1 = "\x1b[0;33m";
string greenBold2 = "\x1b[0;34m";
string greenBold3 = "\x1b[0;35m";
string greenBold4 = "\x1b[0;36m";
string done = "\x1b[0m"; /// normal text
// [0; is normal
// [1; is Bold
// [4; is Underline  (bit combine?)
string color(string input, string theColor) {
	return theColor ~ input ~ done;
}

string colorizeAll(string input, string color) {
	return color ~ input ~ done;
}

string colorizeWord(string input, string word, string color) {
	import std.regex, std.string : splitLines;

	auto r = regex(word);
	string data;
	foreach (line; input.splitLines) {
		//	writeln("---------------", line, "--------------");
		auto captures = line.matchFirst(r);
		string pre = captures.pre ~ color;
		string post = done ~ captures.post;
		data ~= pre ~ captures[0] ~ post ~ "\n";
	}
	return data;
}

string colorizeParenthesis(string input, string color) { // WHAT IF there's MULTIPLE in a line?
	import std.regex, std.string : splitLines;

	auto r = ctRegex!(r"\((.*)\)");
	string data;
	foreach (line; input.splitLines) {
		//	writeln("---------------", line, "--------------");
		auto captures = line.matchFirst(r);
		string pre = captures.pre ~ color;
		string post = done ~ captures.post;
		data ~= pre ~ captures[0] ~ post ~ "\n";
	}
	return data;
}


void commandBuild() {
	ProfileConfiguration[string] pConfigs = runToml();
	verboseWriteln(pConfigs);
	version (Windows) string binaryExtension = ".obj";
	version (linux) string binaryExtension = ".o";
	string filesList = "";
	string filesObjList = "";
	auto targetOS = exeConfig.selectedTargetOS;
	auto profile = exeConfig.selectedProfile;
	auto compiler = exeConfig.selectedCompiler;
	verboseWriteln("");
	displayQuote();
	verboseWriteln("");
	verboseWriteln("Files to compile [", targetOS, "]");
	foreach (t; tConfigs)
		verboseWriteln(t.sourceFilesFound);
	foreach (file; tConfigs[targetOS].sourceFilesFound2) {
		filesList ~= file.fullPathAndName ~ " "; //file ~ " ";
		filesObjList ~= tConfigs[targetOS].intermediatePath ~ file.filename.replace(".d", binaryExtension) ~ " ";
	}
	verboseWriteln("filesObjList - ", filesObjList);
	verboseWritefln("Files List \"%s\"\n", filesList);
	auto fcl = new FileCacheList(tConfigs[targetOS].sourceFilesFound);
	string[] changedFiles = fcl.getDifferences();
	writeln("Changed files detected:");
	foreach (f; changedFiles)
		writeln("\t", f);
	writeln();
	verboseWriteln("Library paths:");
	string libPathList = "";
	foreach (libpath; tConfigs[targetOS].libPaths) {
		switch (tConfigs[targetOS].target) {
		case ("linux"):
			libPathList ~= "-L-L" ~ libpath ~ " ";
			break;
		case ("windows"):
			libPathList ~= "-L/LIBPATH:" ~ libpath ~ " ";
			break;
		case ("macosx"):
			assert(0, "macosx not tested");
		default:
			assert(0, format("invalid target name [%s]", profile));
		}
	}
	verboseWritefln("\t\"%s\"", libPathList);
	verboseWriteln("");
	writefln("Buildname: %s (%s/%s)", profile, targetOS, compiler);
	writeln("");

	immutable string flags = pConfigs[profile].mode;
	string runString;
	bool doCachedCompile = true;

	string fileExtension;
	if (exeConfig.selectedTargetOS == "windows") {
		fileExtension = ".exe";
	} else {
		fileExtension = "";
	}

	if (!doCachedCompile) {
		runString =
			"dmd -of=" ~ pConfigs[profile].outputFilename ~ fileExtension ~
			" " ~ flags ~ " " ~ pConfigs[exeConfig.selectedProfile].mode ~ " " ~ filesList ~ " " ~ libPathList ~ " " ~
			exeConfig.extraCompilerFlags ~ " " ~ exeConfig.extraLinkerFlags;

		if (exeConfig.doRunCompiler) {
			auto dmd = executeShell(runString);
			if (dmd.status != 0) {
				writeln("Compilation %s %s:\n %s", "\x1b[1;31m", color("failed", redBold), dmd
						.output);
			} else {
				writefln("Writing to [%s]", pConfigs[profile].outputFilename ~ fileExtension);
				writeln("Compilation ", color(greenBold, "succeeded"), ":\n\n", dmd.output);
				writeln();
				exeConfig.didCompileSucceed = true;
				fcl.saveResults();
			}
		} else {
			writeln("Would have tried to execute the following string:");
			writeln("\t", runString);
		}
	} else {
		writeln("Attempting incremental compile.\n");

		bool stopOnFirstError = true; /// do we stop on the first errored compile, or attempt all? exeConfig option?
		bool hasErrorOccurred = false;
		if (exeConfig.doParallelCompile == false) {
			writeln(" - single-threaded mode:");
			foreach (file; changedFiles) {

				string includePathsStr;
				foreach (p; tConfigs[targetOS].includePaths)
					includePathsStr ~= format("-I%s ", p);

				string execString = format("dmd -c %s %s -od=%s %s %s",
					includePathsStr,
					pConfigs[exeConfig.selectedProfile].mode,
					tConfigs[targetOS].intermediatePath,
					file,
					libPathList); //-od doesn't seem to even do anything

				if (exeConfig.doRunCompiler) {
					verboseWriteln("trying to execute:\t", execString);
					auto exec = executeShell(execString);
					if (exec.status != 0) {
						writefln("Compilation of %s %s:\n%s", color(file, greenBold3), color("failed", redBold), exec
								.output.colorizeParenthesis(redBold).colorizeWord("Error", redBold));

						hasErrorOccurred = true;
						if (stopOnFirstError)
							break;
					} else {
						writefln("Compilation of %s succeeded.", color(file, greenBold3));
					}
				} else {
					writeln("Would have tried to execute (file to obj):\n\n\t", execString);
				}
			}

			if (hasErrorOccurred) {
				writeln("Individual file compilation failed.");
				return;
			}
		} else {
			writeln(" - multi threaded mode");
			// TODO ?
			// Also, if we need a dependency graph of build order, we could figure one
			// out either automatically (just keep compiling random ones until the order works), or allow manual.

			// we might want to store each ones stdout/stderr and display them sequentually so there's no
			// stdout race conditions, and also only display stderr of those that fail.

			try {
				// COMPILE INTERMEDIATES.
				foreach (immutable file; taskPool.parallel(changedFiles)) {
					immutable FilePath filepath = FilePath(file);
					string outputFileStr = tConfigs[targetOS].intermediatePath ~ filepath.basename ~ binaryExtension;
					string includePathsStr;
					foreach (p; tConfigs[targetOS].includePaths)
						includePathsStr ~= format("-I%s ", p);

					writeln("exeConfig.selectedProfile:", exeConfig.selectedProfile);
					writeln("pConfigs:", pConfigs);
					string execString = format("dmd -c %s -od=%s %s %s %s -of=%s", // does -od even work??
						includePathsStr,
						tConfigs[targetOS].intermediatePath,
						pConfigs[exeConfig.selectedProfile].mode,
						file,
						libPathList,
						outputFileStr);
					// color codes https://gist.github.com/JBlond/2fea43a3049b38287e5e9cefc87b2124

					if (exeConfig.doRunCompiler) {
						verboseWriteln("trying to execute:\n\t", execString);
						auto exec = executeShell(execString);
						if (exec.status != 0) {
							//writefln("Compilation of %s failed:\n%s", file, exec.output);
							writeln();
							string msgError = exec.output.colorizeWord("Error", redBold).colorizeParenthesis(
								greenBold2);

							//auto msgError = captures.pre ~ "\x1b[1;31m" ~ captures[0] ~ "\x1b[1;30m" ~ captures.post;
							// NOTE: We could replace this with findSplit most likely if we want to remove regex.

							writefln("Compilation of %s %s", color(file, greenBold4), color("failed", redBold));
							writefln(
								"==========================================================================");
							writefln("%s", msgError);
							if (exeConfig.makeBellOnError)
								writefln("\007"); // MAKE BELL SOUND
							hasErrorOccurred = true;

							//if(stopOnFirstError)break; // can't do breaks in parallel foreach
						} else {
							writefln("Compilation of %s succeeded.", file);
							fcl.saveResults();

						}
					} else {
						writeln("Would have tried to execute (file to obj):\n\t", execString);
					}
				}
			} catch (Exception e) {
				writeln(e);
				assert(false);
			}

			if (hasErrorOccurred) {
				writeln("\nIndividual file compilation \x1b[1;31mfailed\x1b[1;30m.");
				return;
			}
		}

		string libs = "";
		string linuxLibraryPrefix = "-L-l";
		string windowsLibraryPrefix = "-L/LIBPATH:";
		//writeln("TARGET OS IS ", targetOS);
		foreach (lib; tConfigs[targetOS].libs) { //TODO: make sure this works for windows
			string prefix;
			if (targetOS == "windows")
				prefix = windowsLibraryPrefix;
			else if (targetOS == "linux")
				prefix = linuxLibraryPrefix;
			else
				assert(0, "excuse me what.");

			libs ~= prefix ~ lib ~ " "; // e.g.  -L-lallegro -> -lallegro -> liballegro.a
		}

		// then if they all succeed, compile the final product.
		string filename = pConfigs[profile].outputFilename ~ fileExtension;
		string outputFileStr = tConfigs[targetOS].projectRootPath ~ filename;
		runString = "dmd -of=" ~ outputFileStr ~
			" " ~ flags ~ " " ~
			filesObjList.replace(
				tConfigs[targetOS].sourcePaths[0],
				tConfigs[targetOS].intermediatePath) ~ " " ~
			libPathList ~ " " ~
			libs ~ " " ~
			exeConfig.extraCompilerFlags ~ " " ~ exeConfig.extraLinkerFlags;

		if (!exeConfig.doRunCompiler) {
			writeln();
			writeln("Would have tried to execute (executable):\n\t", runString);
		} else {
			writeln("\nTrying to execute:\n\t", runString);
			auto dmd = executeShell(runString);
			if (dmd.status != 0) {
				writeln();
				writeln("\nCompilation ", color("failed", redBold), "\n", dmd.output);
			} else {
				writeln("\nCompilation ", color("succeeded", greenBold), ".");

				if (exeConfig.runProgramAfterward)
					{
					runProgram(outputFileStr, targetOS);
					}
				}
			}
		}
}

int runProgram(string outputFileStr, string targetOS){
	writefln("runProgram(%s,%s):", outputFileStr, targetOS);
	auto s = spawnShell(
		outputFileStr, 
		config:Config.stderrPassThrough,
		workDir:tConfigs[targetOS].projectRootPath);

	wait(s);

	return 0;
}

//void runProgram(string command){
//	auto result = executeShell(command, );
//	}

// __gshared because taskpool.parallel is too stupid to have access to these with TLS.
__gshared GlobalConfiguration globalConfig;
__gshared TargetConfiguration[string] tConfigs;
__gshared ExeConfigType exeConfig;

void setup() {
	exeConfig = new ExeConfigType("");
	setVerboseModeVariable(&exeConfig.doPrintVerbose);
	setupDefaultOSstring();
}

void setupDefaultOSstring() {
	exeConfig.selectedTargetOS = "excuse me, wat"; // default fail case.
	version (Windows)
		exeConfig.selectedTargetOS = "windows";
	version (linux)
		exeConfig.selectedTargetOS = "linux";
	version (MacOSX)
		exeConfig.selectedTargetOS = "macosx";
}

int main(string[] args) {
	setup();
	if (args.length > 1) {
		writefln("masterBuilder %s", args[1 .. $]);
		parseCommandline(args[1 .. $]);
	} else {
		writefln("masterBuilder");
		displayHelp();
	}
	return 0;
}
