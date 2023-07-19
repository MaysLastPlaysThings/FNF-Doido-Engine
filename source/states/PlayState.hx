package states;

import data.Discord.DiscordClient;
import flixel.FlxG;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxRect;
import flixel.system.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import data.*;
import data.SongData.SwagSong;
import data.SongData.SwagSection;
import data.chart.*;
import data.GameData.MusicBeatState;
import gameObjects.*;
import gameObjects.hud.*;
import gameObjects.hud.note.*;
import states.editors.ChartingState;
import subStates.*;

using StringTools;

class PlayState extends MusicBeatState
{
	// song stuff
	public static var SONG:SwagSong;
	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var musicList:Array<FlxSound> = [];

	public static var songLength:Float = 0;

	// 
	public static var assetModifier:String = "base";
	public static var health:Float = 1;
	// score, misses, accuracy and other stuff
	// are on the Timings.hx class!!

	// objects
	public var stageBuild:Stage;

	public var characters:Array<Character> = [];
	public var dad:Character;
	public var boyfriend:Character;
	public var gf:Character;

	// strumlines
	public var strumlines:FlxTypedGroup<Strumline>;
	public var bfStrumline:Strumline;
	public var dadStrumline:Strumline;

	// hud
	public var hudBuild:HudClass;

	// cameras!!
	public var camGame:FlxCamera;
	public var camHUD:FlxCamera;
	public var camOther:FlxCamera; // used so substates dont collide with camHUD.alpha or camHUD.visible
	public static var defaultCamZoom:Float = 1.0;

	public var camFollow:FlxObject = new FlxObject();

	public static var paused:Bool = false;

	function resetStatics()
	{
		health = 1;
		defaultCamZoom = 1.0;
		assetModifier = "base";
		Timings.init();
		paused = false;
	}

	override public function create()
	{
		super.create();
		CoolUtil.playMusic();
		resetStatics();
		if(SONG == null)
			SONG = SongData.loadFromJson("ugh");

		if(SONG.song.toLowerCase() == "collision")
			assetModifier = "pixel";

		// preloading stuff
		Paths.preloadPlayStuff();
		Rating.preload(assetModifier);
		SplashNote.resetStatics();

		// adjusting the conductor
		Conductor.setBPM(SONG.bpm);
		Conductor.mapBPMChanges(SONG);

		// setting up the cameras
		camGame = new FlxCamera();
		
		camHUD = new FlxCamera();
		camHUD.bgColor.alphaFloat = 0;

		camOther = new FlxCamera();
		camOther.bgColor.alpha = 0;

		// adding the cameras
		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);

		// default camera
		FlxG.cameras.setDefaultDrawTarget(camGame, true);

		//camGame.zoom = 0.6;

		stageBuild = new Stage();
		stageBuild.reloadStageFromSong(SONG.song);
		add(stageBuild);

		camGame.zoom = defaultCamZoom;

		dad = new Character();
		dad.reloadChar(SONG.player2, false);
		dad.setPosition(50, 700);
		dad.y -= dad.height;

		boyfriend = new Character();
		boyfriend.reloadChar(SONG.player1, true);
		boyfriend.setPosition(850, 700);
		boyfriend.y -= boyfriend.height;

		characters.push(dad);
		characters.push(boyfriend);

		for(char in characters)
		{
			char.x += char.globalOffset.x;
			char.y += char.globalOffset.y;
		}

		var addList:Array<FlxBasic> = [dad, boyfriend, stageBuild.foreground];

		for(item in addList)
			add(item);

		followCamera(dad);

		FlxG.camera.follow(camFollow, LOCKON, 1);
		FlxG.camera.focusOn(camFollow.getPosition());

		hudBuild = new HudClass();
		hudBuild.cameras = [camHUD];
		add(hudBuild);

		// strumlines
		strumlines = new FlxTypedGroup();
		strumlines.cameras = [camHUD];
		add(strumlines);

		//strumline.scrollSpeed = 4.0; // 2.8
		var strumPos:Array<Float> = [FlxG.width / 2, FlxG.width / 4];
		var downscroll:Bool = SaveData.data.get("Downscroll");

		dadStrumline = new Strumline(strumPos[0] - strumPos[1], dad, downscroll, false, true, assetModifier);
		dadStrumline.ID = 0;
		strumlines.add(dadStrumline);

		bfStrumline = new Strumline(strumPos[0] + strumPos[1], boyfriend, downscroll, true, false, assetModifier);
		bfStrumline.ID = 1;
		strumlines.add(bfStrumline);

		if(SaveData.data.get("Middlescroll"))
		{
			dadStrumline.x -= strumPos[0]; // goes offscreen
			bfStrumline.x  -= strumPos[1]; // goes to the middle
		}

		for(strumline in strumlines.members)
		{
			strumline.scrollSpeed = SONG.speed;
			strumline.updateHitbox();
		}

		hudBuild.updateHitbox(bfStrumline.downscroll);

		var daSong:String = SONG.song.toLowerCase();

		inst = new FlxSound();
		inst.loadEmbedded(Paths.inst(daSong), false, false);

		vocals = new FlxSound();
		if(SONG.needsVoices)
		{
			vocals.loadEmbedded(Paths.vocals(daSong), false, false);
		}

		songLength = inst.length;
		function addMusic(music:FlxSound):Void
		{
			FlxG.sound.list.add(music);

			if(music.length > 0)
			{
				musicList.push(music);

				if(music.length < songLength)
					songLength = music.length;
			}

			music.play();
			music.stop();
		}

		addMusic(inst);
		addMusic(vocals);

		//Conductor.setBPM(160);
		Conductor.songPos = -Conductor.crochet * 5;

		var unspawnNotesAll:Array<Note> = ChartLoader.getChart(SONG);

		for(note in unspawnNotesAll)
		{
			var thisStrumline = dadStrumline;
			for(strumline in strumlines)
			{
				if(note.strumlineID == strumline.ID)
					thisStrumline = strumline;
			}

			//var direc = NoteUtil.getDirection(note.noteData);
			var thisStrum = thisStrumline.strumGroup.members[note.noteData];
			var thisChar = thisStrumline.character;

			var noteAssetMod:String = assetModifier;

			//noteAssetMod = ["base", "doido", "pixel"][FlxG.random.int(0, 2)];

			note.reloadNote(note.songTime, note.noteData, note.noteType, noteAssetMod);

			note.onHit = function()
			{
				// when the player hits notes
				vocals.volume = 1;
				if(thisStrumline.isPlayer)
				{
					popUpRating(note, false);
				}

				if(!note.isHold)
				{
					var noteDiff:Float = Math.abs(note.songTime - Conductor.songPos);
					if(noteDiff <= Timings.timingsMap.get("sick")[0] || thisStrumline.botplay)
					{
						thisStrumline.playSplash(note);
					}
				}

				// anything else
				note.isPressing = false;
				note.gotHit = true;
				if(note.holdLength > 0)
					note.gotHold = true;

				if(!note.isHold)
				{
					//note.alpha = 0;
					note.visible = false;
					thisStrum.playAnim("confirm");
				}

				if(thisChar != null && !note.isHold)
				{
					thisChar.playAnim(thisChar.singAnims[note.noteData], true);
					thisChar.holdTimer = 0;

					/*if(note.noteType != 'none')
						thisChar.playAnim('hey');*/
				}
			};
			note.onMiss = function()
			{
				if(thisStrumline.botplay) return;

				note.gotHit = false;
				note.gotHold= false;
				note.canHit = false;
				note.isPressing = false;
				note.alpha = 0.15;

				// put global stuff inside onlyOnce
				var onlyOnce:Bool = false;

				if(!note.isHold)
					onlyOnce = true;
				else
				{
					if(!note.isHoldEnd && note.parentNote.gotHit)
						onlyOnce = true;
				}

				if(onlyOnce)
				{
					vocals.volume = 0;

					FlxG.sound.play(Paths.sound('miss/missnote' + FlxG.random.int(1, 3)), 0.55);

					if(thisChar != null)
					{
						thisChar.playAnim(thisChar.missAnims[note.noteData], true);
						thisChar.holdTimer = 0;
					}

					// when the player misses notes
					if(thisStrumline.isPlayer)
					{
						popUpRating(note, true);
					}
				}
			};
			// only works on long notes!!
			note.onHold = function()
			{
				vocals.volume = 1;
				note.gotHold = true;

				// if not finished
				if(note.holdHitLength < note.holdLength - Conductor.stepCrochet)
				{
					thisStrum.playAnim("confirm");

					thisChar.playAnim(thisChar.singAnims[note.noteData], true);
					thisChar.holdTimer = 0;
				}
			}

			thisStrumline.addSplash(note);

			thisStrumline.unspawnNotes.push(note);
		}

		switch(SONG.song.toLowerCase())
		{
			case "disruption":
				// faz o dad voar só na disruption
				var initialPos = [dad.x + 100, dad.y - 100];
				var flyTime:Float = 0;
				dad._update = function(elapsed:Float)
				{
					flyTime += elapsed * Math.PI;
					dad.y = initialPos[1] + Math.sin(flyTime) * 100;
					dad.x = initialPos[0] + Math.cos(flyTime) * 100;
				}
		}

		// Updating Discord Rich Presence
		DiscordClient.changePresence("Playing: " + SONG.song.toUpperCase().replace("-", " "), null);

		startCountdown();
	}

	public var startedSong:Bool = false;

	public function startCountdown()
	{
		var daCount:Int = 0;

		var countTimer = new FlxTimer().start(Conductor.crochet / 1000, function(tmr:FlxTimer)
		{
			Conductor.songPos = -Conductor.crochet * (4 - daCount);

			if(daCount == 4)
			{
				startSong();
			}

			if(daCount != 4)
			{
				var soundName:String = ["3", "2", "1", "Go"][daCount];

				FlxG.sound.play(Paths.sound("countdown/intro" + soundName));

				/*var hehe = new gameObjects.menu.Alphabet(0, 0, ["3", "2", "1", "GO"][daCount], true);
				hehe.cameras = [camHUD];
				hehe.screenCenter();
				hudBuild.add(hehe);*/
				if(daCount >= 1)
				{
					var countName:String = ["ready", "set", "go"][daCount - 1];

					var countSprite = new FlxSprite();
					countSprite.loadGraphic(Paths.image("hud/base/" + countName));
					countSprite.scale.set(0.65,0.65); countSprite.updateHitbox();
					countSprite.screenCenter();
					countSprite.cameras = [camHUD];
					hudBuild.add(countSprite);

					//new FlxTimer().start(Conductor.stepCrochet * 3.8 / 1000, function(tmr:FlxTimer)
					FlxTween.tween(countSprite, {alpha: 0}, Conductor.stepCrochet * 2.8 / 1000, {
						startDelay: Conductor.stepCrochet * 1 / 1000,
						onComplete: function(twn:FlxTween)
						{
							countSprite.destroy();
						}
					});
				}
			}

			//trace(daCount);

			daCount++;
		}, 5);
	}

	public function startSong()
	{
		startedSong = true;
		for(music in musicList)
		{
			music.stop();
			music.play();

			if(paused) {
				music.pause();
			}
		}
	}

	override function openSubState(state:FlxSubState)
	{
		super.openSubState(state);
		if(startedSong)
		{
			for(music in musicList)
			{
				music.pause();
			}
		}
	}

	override function closeSubState()
	{
		activateTimers(true);
		super.closeSubState();
		if(startedSong)
		{
			for(music in musicList)
			{
				music.play();
			}
			syncSong(true);
		}
	}

	// for pausing timers and tweens
	function activateTimers(apple:Bool = true)
	{
		FlxTimer.globalManager.forEach(function(tmr:FlxTimer)
		{
			if(!tmr.finished)
				tmr.active = apple;
		});

		FlxTween.globalManager.forEach(function(twn:FlxTween)
		{
			if(!twn.finished)
				twn.active = apple;
		});
	}

	public function popUpRating(note:Note, miss:Bool = false)
	{
		var noteDiff:Float = Math.abs(note.songTime - Conductor.songPos);
		if(note.isHold && !miss)
			noteDiff = 0;

		var rating:String = Timings.diffToRating(noteDiff);
		var judge:Float = Timings.diffToJudge(noteDiff);
		if(miss)
		{
			rating = "miss";
			judge = Timings.timingsMap.get('miss')[1];
		}

		// handling stuff
		health += 0.05 * judge;
		Timings.score += Math.floor(100 * judge);
		Timings.addAccuracy(judge);

		if(miss)
		{
			Timings.misses++;

			if(Timings.combo > 0)
				Timings.combo = 0;
			Timings.combo--;
		}
		else
		{
			if(Timings.combo < 0)
				Timings.combo = 0;
			Timings.combo++;

			if(rating == "shit")
			{
				note.onMiss();
			}
		}

		var daRating = new Rating(rating, Timings.combo, note.assetModifier);

		if(SaveData.data.get("Ratings on HUD"))
		{
			hudBuild.add(daRating);
			
			for(item in daRating.members)
				item.cameras = [camHUD];

			var daX:Float = (FlxG.width / 2) - 64;
			if(SaveData.data.get("Middlescroll"))
				daX -= FlxG.width / 4;

			daRating.setPos(daX, FlxG.height / 2);
		}
		else
		{
			add(daRating);

			daRating.setPos(boyfriend.x, boyfriend.y);
		}

		hudBuild.updateText();
	}

	// if youre holding a note
	public var isSinging:Bool = false;

	override public function update(elapsed:Float)
	{
		super.update(elapsed);
		camGame.followLerp = elapsed * 3;

		if(Controls.justPressed("PAUSE"))
		{
			pauseSong();
		}

		if(Controls.justPressed("RESET"))
			startGameOver();

		if(FlxG.keys.justPressed.SEVEN)
		{
			if(ChartingState.SONG.song != SONG.song)
				ChartingState.curSection = 0;

			ChartingState.SONG = SONG;
			Main.switchState(new ChartingState());
		}

		/*if(FlxG.keys.justPressed.SPACE)
		{
			for(strumline in strumlines.members)
			{
				strumline.downscroll = !strumline.downscroll;
				strumline.updateHitbox();
			}
			hudBuild.updateHitbox(bfStrumline.downscroll);
		}*/

		//strumline.scrollSpeed = 2.8 + Math.sin(FlxG.game.ticks / 500) * 1.5;

		//if(song.playing)
		//	Conductor.songPos = song.time;
		// syncSong
		Conductor.songPos += elapsed * 1000;

		var pressed:Array<Bool> = [
			Controls.pressed("LEFT"),
			Controls.pressed("DOWN"),
			Controls.pressed("UP"),
			Controls.pressed("RIGHT")
		];
		var justPressed:Array<Bool> = [
			Controls.justPressed("LEFT"),
			Controls.justPressed("DOWN"),
			Controls.justPressed("UP"),
			Controls.justPressed("RIGHT")
		];
		var released:Array<Bool> = [
			Controls.released("LEFT"),
			Controls.released("DOWN"),
			Controls.released("UP"),
			Controls.released("RIGHT")
		];

		isSinging = false;

		// strumline handler!!
		for(strumline in strumlines.members)
		{
			for(strum in strumline.strumGroup)
			{
				if(strumline.isPlayer && !strumline.botplay)
				{
					if(pressed[strum.strumData])
					{
						if(!["pressed", "confirm"].contains(strum.animation.curAnim.name))
							strum.playAnim("pressed");
						
						if(strum.animation.curAnim.name == "confirm")
							isSinging = true;
					}
					else
						strum.playAnim("static");
				}
				else
				{
					// how botplay handles it
					if(strum.animation.curAnim.name == "confirm"
					&& strum.animation.curAnim.finished)
						strum.playAnim("static");
				}
			}

			for(unsNote in strumline.unspawnNotes)
			{
				var spawnTime:Float = 1000;

				if(unsNote.songTime - Conductor.songPos <= spawnTime
				&& unsNote.canHit && !unsNote.gotHit && !unsNote.gotHold)
					strumline.addNote(unsNote);
			}
			for(note in strumline.allNotes)
			{
				var despawnTime:Float = 300;

				if(Conductor.songPos >= note.songTime + note.holdLength + Conductor.stepCrochet + despawnTime)
				{
					if(!note.gotHit && !note.gotHold && note.canHit)
						note.onMiss();

					if(!note.isPressing)
						strumline.removeNote(note);
				}
			}

			// downscroll
			var downMult:Int = (strumline.downscroll ? -1 : 1);

			for(note in strumline.noteGroup)
			{
				var thisStrum = strumline.strumGroup.members[note.noteData];

				note.x = thisStrum.x + note.noteOffset.x;
				note.y = thisStrum.y + (thisStrum.height / 12 * downMult) + (note.noteOffset.y * downMult);

				/*note.scale.set(
					1 + Math.sin(FlxG.game.ticks / 64) * 0.3,
					1 - Math.sin(FlxG.game.ticks / 64) * 0.3
				);*/
				//note.angle = flixel.math.FlxMath.lerp(note.angle, FlxG.random.int(-360, 360), elapsed * 8);

				note.y += downMult * ((note.songTime - Conductor.songPos) * (strumline.scrollSpeed * 0.45));

				if(Conductor.songPos >= note.songTime + Timings.timingsMap.get("good")[0]
				&& !note.gotHit && note.canHit)
				{
					note.onMiss();
				}

				if(strumline.botplay)
				{
					if(note.songTime - Conductor.songPos <= 0 && !note.gotHit)
						note.onHit();
				}

				// whatever
				if(note.scrollSpeed != strumline.scrollSpeed)
					note.scrollSpeed = strumline.scrollSpeed;
			}

			for(hold in strumline.holdGroup)
			{
				if(hold.scrollSpeed != strumline.scrollSpeed)
				{
					hold.scrollSpeed = strumline.scrollSpeed;

					if(!hold.isHoldEnd)
					{
						var newHoldSize:Array<Float> = [
							hold.frameWidth * hold.scale.x,
							(hold.holdLength - (Conductor.stepCrochet / 2)) * (strumline.scrollSpeed * 0.45)
						];

						hold.setGraphicSize(
							Math.floor(newHoldSize[0]),
							Math.floor(newHoldSize[1])
						);
					}

					hold.updateHitbox();
				}

				hold.flipY = strumline.downscroll;
				if(hold.assetModifier == "base")
					hold.flipX = hold.flipY;

				if(hold.parentNote != null)
				{
					var thisStrum = strumline.strumGroup.members[hold.noteData];
					var holdParent = hold.parentNote;

					if(!hold.isHoldEnd)
					{
						hold.x = (holdParent.x + holdParent.width / 2 - hold.width / 2) + hold.noteOffset.x;
						hold.y = holdParent.y + holdParent.height / 2;
					}
					else
					{
						hold.x = holdParent.x;
						hold.y = holdParent.y + (strumline.downscroll ? 0 : holdParent.height) + (-downMult * 0.5);
					}

					if(strumline.downscroll)
						hold.y -= hold.height;

					// input!!
					if(!holdParent.canHit && hold.canHit)
						hold.onMiss();

					var pressedCheck:Bool = (pressed[hold.noteData] && holdParent.gotHold && hold.canHit);

					if(!strumline.isPlayer || strumline.botplay)
						pressedCheck = (holdParent.gotHold && hold.canHit);

					if(hold.isHoldEnd)
						pressedCheck = (holdParent.gotHold && holdParent.canHit);

					if(pressedCheck)
					{
						hold.holdHitLength = Conductor.songPos - hold.songTime;
						//trace('${hold.holdHitLength} / ${hold.holdLength}');

						hold.isPressing = true;
						
						var daRect = new FlxRect(
							0,
							0,
							hold.frameWidth,
							hold.frameHeight
						);

						var center:Float = (thisStrum.y + thisStrum.height / 2);

						if(!strumline.downscroll)
						{
							if(hold.y < center)
								daRect.y = (center - hold.y) / hold.scale.y;
						}
						else
						{
							if(hold.y + hold.height > center)
								daRect.y = ((hold.y + hold.height) - center) / hold.scale.y;
						}

						hold.clipRect = daRect;

						hold.onHold();
					}

					if(strumline.isPlayer && !strumline.botplay)
					{
						if(released.contains(true))
						{					
							if(released[hold.noteData] && hold.canHit && holdParent.gotHold && !hold.isHoldEnd)
							{
								thisStrum.playAnim("static");

								if(hold.holdHitLength >= hold.holdLength - Conductor.stepCrochet)
									hold.onHit();
								else
									hold.onMiss();
							}
						}
					}
					else
					{
						if(holdParent.gotHold && !hold.isHoldEnd)
						{
							if(hold.holdHitLength >= hold.holdLength - Conductor.stepCrochet)
								hold.onHit();
							else
							{
								hold.onHold();
								//thisStrum.playAnim("confirm");
							}
						}
					}
				}
			}

			if(justPressed.contains(true) && !strumline.botplay && strumline.isPlayer)
			{
				for(i in 0...justPressed.length)
				{
					if(justPressed[i])
					{
						var possibleHitNotes:Array<Note> = []; // gets the possible ones
						var canHitNote:Note = null;

						for(note in strumline.noteGroup)
						{
							var noteDiff:Float = (note.songTime - Conductor.songPos);

							if(noteDiff <= Timings.minTiming && note.canHit && !note.gotHit && note.noteData == i)
							{
								possibleHitNotes.push(note);
								canHitNote = note;
							}
						}

						// if the note actually exists then you got it
						if(canHitNote != null)
						{
							for(note in possibleHitNotes)
							{
								if(note.songTime < canHitNote.songTime)
									canHitNote = note;
							}

							canHitNote.onHit();
						}
						else
						{
							// ghost tapped lol
							if(!SaveData.data.get("Ghost Tapping"))
							{
								vocals.volume = 0;
								var thisChar = strumline.character;
								if(thisChar != null)
								{
									thisChar.playAnim(thisChar.missAnims[i], true);
									thisChar.holdTimer = 0;
								}

								var note = new Note();
								note.reloadNote(0,0,"none",assetModifier);
								FlxG.sound.play(Paths.sound('miss/missnote' + FlxG.random.int(1, 3)), 0.55);
								popUpRating(note, true);
							}
						}
					}
				}
			}

			// dumb stuff!!!
			if(SONG.song.toLowerCase() == "disruption")
			{
				for(strum in strumline.strumGroup)
				{
					var daTime:Float = (FlxG.game.ticks / 1000);

					var strumMult:Int = (strum.strumData % 2 == 0) ? 1 : -1;

					strum.x = strum.initialPos.x + Math.sin(daTime) * 20 * strumMult;
					strum.y = strum.initialPos.y + Math.cos(daTime) * 20 * strumMult;

					strum.scale.x = strum.strumSize + Math.sin(daTime) * 0.4;
					strum.scale.y = strum.strumSize - Math.sin(daTime) * 0.4;
				}
				for(note in strumline.allNotes)
				{
					var thisStrum = strumline.strumGroup.members[note.noteData];

					note.scale.x = thisStrum.scale.x;
					if(!note.isHold)
						note.scale.y = thisStrum.scale.y;
				}
			}
			/*else
			{
				var daPos = (Conductor.songPos);

				while(daPos > Conductor.crochet * 1.5)
				{
					daPos -= Conductor.crochet * 1.5;
				}

				var strumY:Float = strumline.downscroll ? FlxG.height : -NoteUtil.noteWidth();
				if(Conductor.songPos > 0)
					strumY += (daPos * downMult * (strumline.scrollSpeed * 0.45));

				for(strum in strumline.strumGroup)
				{
					strum.y = strumY;
				}
			}*/
		}

		var lastSteps:Int = 0;
		var curSection:SwagSection = null;
		for(section in SONG.notes)
		{
			if(curStep >= lastSteps)
				curSection = section;

			lastSteps += section.lengthInSteps;
		}
		if(curSection != null)
		{
			if(curSection.mustHitSection)
				followCamera(boyfriend);
			else
				followCamera(dad);
		}

		if(health <= 0)
		{
			startGameOver();
		}

		camGame.zoom = FlxMath.lerp(camGame.zoom, defaultCamZoom, elapsed * 6);
		camHUD.zoom  = FlxMath.lerp(camHUD.zoom,  1.0, elapsed * 6);

		health = FlxMath.bound(health, 0, 2); // bounds the health
	}

	public function followCamera(?char:Character, ?offsetX:Float = 0, ?offsetY:Float = 0)
	{
		camFollow.setPosition(0,0);

		if(char != null)
		{
			var playerMult:Int = (char.isPlayer ? -1 : 1);

			camFollow.setPosition(char.getMidpoint().x + (200 * playerMult), char.getMidpoint().y - 20);

			camFollow.x += char.cameraOffset.x * playerMult;
			camFollow.y += char.cameraOffset.y;
		}

		camFollow.x += offsetX;
		camFollow.y += offsetY;
	}

	override function beatHit()
	{
		super.beatHit();
		for(change in Conductor.bpmChangeMap)
		{
			if(curStep >= change.stepTime && Conductor.bpm != change.bpm)
				Conductor.setBPM(change.bpm);
		}
		hudBuild.beatHit(curBeat);

		if(curBeat % 4 == 0)
		{
			camGame.zoom += 0.05;
			camHUD.zoom += 0.025;
		}
		if(curBeat % 2 == 0)
		{
			for(char in characters)
			{
				var canIdle = (char.holdTimer >= char.holdLength);

				if(char.isPlayer)
				{
					if(isSinging)
						canIdle = false;
				}

				if(canIdle)
					char.dance();
			}
		}
	}

	override function stepHit()
	{
		super.stepHit();
		syncSong();
	}

	public function syncSong(?forced:Bool = false):Void
	{
		if(!startedSong) return;

		for(music in musicList)
		{
			if(music.playing && Conductor.songPos < music.length)
			{
				if(Math.abs(Conductor.songPos - music.time) >= 40 || forced)
				{
					// makes everyone sync to the instrumental
					trace("synced song");
					Conductor.songPos = inst.time;
					
					if(music != inst)
					{
						music.time = inst.time;
						music.play();
					}
				}
			}
		}

		checkEndSong();
	}

	public function checkEndSong(?forced:Bool = false):Void
	{
		// works like endSong() if forced
		if(Conductor.songPos >= songLength || forced)
		{
			Highscore.addScore(SONG.song.toLowerCase(), {
				score: 		Timings.score,
				accuracy: 	Timings.accuracy,
				misses: 	Timings.misses,
			});
			Main.switchState(new MenuState());
		}
	}

	override function onFocusLost():Void
	{
		if(!paused && !isDead) pauseSong();
		super.onFocusLost();
	}

	public function pauseSong()
	{
		paused = true;
		activateTimers(false);
		openSubState(new PauseSubState());
	}

	public var isDead:Bool = false;

	public function startGameOver()
	{
		if(isDead) return;

		isDead = true;
		activateTimers(false);
		persistentDraw = false;
		openSubState(new GameOverSubState(boyfriend));
	}
}