require_relative 'base_stats'
require_relative 'roll'

class Character
	attr_reader :name, :fullName, :race, :levels

	def initialize(obj, player)
		@player = player
		# obj.each_pair { |name, val| 
		# 	instance_variable_set("@#{name}", val)
		# }

		@name = obj['name']
		@fullName = obj['fullName'] || obj['name']

		@race = obj['race']
		@levels = obj['levels'] || []
		@alignment = obj['alignment'] || "None"
		@background = obj['background'] || "None"
		@inspiration = obj['inspiration'] || 0

		@armourClass = obj['armourClass'] || 10 + (obj['abilities']['dex']-10)/2
		@initiative = obj['initiative'] || obj['abilities']['dex']
		@speed = obj['speed']

		@maxHitpoints = obj['maxHitpoints']
		@hitpoints = obj['hitpoints'] || obj['maxHitpoints']
		@tempHitpoints = obj['tempHitpoints'] || 0

		@abilities = obj['abilities']

		@skills = obj['skills'] || []
		@saves = obj['saves'] || []
		@weaponProficiencies = obj['weaponProficiencies'] || []
		@armourProficiencies = obj['armourProficiencies'] || []
		@toolProficiencies = obj['toolProficiencies'] || []
		@languages = obj['languages'] || ["Common"]
		@expertise = obj['expertise'] || []

		@features = obj['features'] || []
		@spells = obj['spells'] || []

		@totalLevel = @levels.sum {|_class| _class['level'] }
		# @spellcastingLevel = @levels.sum { |_class|
		# 	if ["Bard","Cleric","Druid","Sorcerer","Wizard"].include? _class['class']
		# 		return _class['level']
		# 	elsif ["Paladin","Ranger"].include? _class['class']
		# 			return (_class['level']-1) / 2
		# 		end				
		# 	elsif ["Eldrich Knight", "Arcane Trickster"].include? classObj["subclass"]
		# 			@spellcastingLevel += 1
		# }
	end

	#Stat Getters
		def proficiencyBonus
			(@totalLevel+7)/4
		end

		def abilityModifier (abilityName)
			(@abilities[abilityName.downcase]-10)/2
		end

		def skillModifier(skill)
			if @proficiencies.include? skill
				return proficiencyBonus + abilityModifier(SkillsRelatedAbility[skill])
			elsif @expertise.include? skill
				return proficiencyBonus * 2 + abilityModifier(SkillsRelatedAbility[skill])
			elsif findFeature("Jack of All Trades")
				return proficiencyBonus / 2 + abilityModifier(SkillsRelatedAbility[skill])
			else
				return abilityModifier(SkillsRelatedAbility[skill])
			end
		end

		def findFeature(name)
			@features.detect { |feature| feature.name == name }
		end

		def savingThrowModifier(abilityName)
			abilityModifier(@abilities[abilityName]) + (saves.include? abilityName ? proficiencyBonus() : 0)
		end

	def levelUp(className)
		classObj = @levels.detect {|x| x['name'].downcase == className.downcase}
		if !classObj
			return "Class does not exist"
		end
		classObj["level"] += 1
		@totalLevel += 1

		#Spellcasting
			# if ["Bard","Cleric","Druid","Sorcerer","Wizard"].include? className
			# 	@spellcastingLevel++
			# 	if [4,10].include? classObj["level"]
			# 		# Learn Cantrip
			# 	end
			# elsif ["Paladin","Ranger"].include? className
			# 	if classObj["level"] == 2 #or classObj["level"] % 2 == 1
			# 		@spellcastingLevel += 1
			# 	end				
			# elsif ["Eldrich Knight", "Arcane Trickster"].include? classObj["subclass"]
			# 	if classObj['level'] == 3 or classObj['level'] % 3 == 1
			# 		@spellcastingLevel += 1
			# 	end
			# 	if classObj['level'] == 10
			# 		#Learn Cantrip
			# 	end
			# elsif "Warlock".eql? className
			# 	if [4,10].include? classObj['level']
			# 		# Learn Cantrip
			# 	end
			# end

		#Ability Score Increase
			if [4,8,12,19].include? classObj["level"]
				#Ask for scores or feat name
				#Valid inputs are one ability name (2 points), two abilites (comma seperated), the name of a feature, or 'list' to list all feature names
				# @abilities[abilities['1']] ++
				# @abilities[abilities['2']] ++
				# @updates["abilities"].update(@abilities)
			end

		#Class Features
			features = Client['classes'].aggregate([
				{ "$match": {"name": className} },
				{ "$unwind": "$features.#{classObj['level']}" },
				{ "$lookup": {
					"from": "features",
					"localField": "features.#{classObj['level']}",
					"foreignField": "name",
					"as": "featureObj"
				}},
				{ "$project": { "feature": { "$arrayElemAt": [ "$featureObj", 0 ] }}},
				{ "$group": {"_id": className, "features": {"$push": "$feature"}}}
			]).first
			puts "Features: #{features}"
			if features
				@features.concat(features['features'])
			end
		#Query subclass feats and apply
			if classObj['subclass']	
				features = Client['classes'].aggregate([
					{ "$match": {"name": className} },
					{ "$unwind": "$subclasses.#{classObj['subclass']}.#{classObj['level']}" },
					{ "$lookup": {
						"from": "features",
						"localField": "features.#{classObj['level']}",
						"foreignField": "name",
						"as": "featureObj"
					}},
					{ "$project": { "feature": { "$arrayElemAt": [ "$featureObj", 0 ] }}},
					{ "$group": {"_id": className, "features": {"$push": "$feature"}}}
				]).first
				puts "Subclass Features: #{features}"
				if features
					@features.concat(features['features'])
				end
			end

		# #Update 
		# 	@updates["levels"].update(@levels)
		# 	@updates["features"].update(@features)
		# #These are the changes needed
		# 	puts @updates
		return "Leveled up"
	end

	def savingThrow(abilityName, difficulty, advantage = "", extra = 0)
		begin
			modifier = extra + abilityModifier(abilityName) + ((@saves.include? abilityName) ? proficiencyBonus : 0)

			if advantage == "advantage"
				roll = rollDouble(true)
			elsif advantage == "disadvantage"
				roll = rollDouble(false)
			else
				roll = roll(20)
			end
			message = "Rolled #{roll}. With a #{modifier > 0 ? "+": ""}#{modifier} modifier, "
			if (roll + modifier >= difficulty or roll == 20) && roll != 1
				message += "you successed"
			else
				message += "you failed"
			end
			return "#{message} with a total score of #{roll + modifier}" 
		rescue
			return "Saving throw did not execute properly, ensure the parameters are the ability name (Str, Dex, Con, Int, Wis, Cha), followed by the difficulty as a whole number"
		end
	end

	def upload
		obj = {
			'name' => @name,
			'fullName' => @fullName,

			'race' => @race,
			'levels' => @levels,
			'alignment' => @alignment,
			'background' => @background,
			'inspiration' => @inspiration,

			'armourClass' => @armourClass,
			'initiative' => @initiative,
			'speed' => @speed,

			'maxHitpoints' => @maxHitpoints,
			'hitpoints' => @hitpoints,
			'tempHitpoints' => @tempHitpoints,

			'abilities' => @abilities,

			'skills' => @skills,
			'saves' => @saves,
			'weaponProficiencies' => @weaponProficiencies,
			'armourProficiencies' => @armourProficiencies,
			'toolProficiencies' => @toolProficiencies,
			'languages' => @languages,
			'expertise' => @expertise,

			'features' => @features,
			'spells' => @spells
		}

		# Complete Rewrite
		Client['characters'].replace_one({ name: @name}, obj, { upsert: true})
		return "Character saved"
	end

	# Proficiencies
		def addProficiency(category, name)
			begin
				if category.eql? "skill"
					if @skills.include?(name)
						return "Already proficient in that skill"
					elsif !Skills.include?(name)
						return "#{name} isn't a valid skill name"
					else
						@skills.push(name)
					end
				elsif category.eql? "save"
					if @save.include?(name)
						return "Already proficient in that save"
					elsif !Abilities.include?(name)
						return "#{name} isn't a valid attribute"
					else
						@skills.push(name)
					end
				elsif category.eql? "weapon"
					if @weaponProficiencies.include?(name)
						return "Already proficient with #{name} weapons"
					else
						@weaponProficiencies.push(name)
					end
				elsif category.eql? "armour"
					if @armourProficiencies.include?(name)
						return "Already proficient with #{name} armour"
					else
						@armourProficiencies.push(name)
					end
				elsif category.eql? "tool"
					if @toolProficiencies.include?(name)
						return "Already proficient with #{name}"
					else
						@toolProficiencies.push(name)
					end
				elsif category.eql? "language"
					if @languages.include?(name)
						return "Already fluent in #{name}"
					else
						@languages.push(name)
					end
				elsif category.eql? "expertise"
					if @toolProficiencies.include?(name)
						return "Already an expert in #{name}"
					else
						@expertise.push(name)
						@skills.delete(name)
						@toolProficiencies.delete(name)
					end
				else
					return "#{category.capitalize} is not a valid category"
				end
				return "#{category.capitalize} proficiency added"
			rescue
				return "Adding proficiency did not execute properly, not sure why, so this message really shouldn't appear"
			end
		end

		def removeProficiency(category, name)
			begin
				if category.eql? "skill"
					@skills.delete(name)
				elsif category.eql? "save"
					@skills.delete(name)
				elsif category.eql? "weapon"
					@weaponProficiencies.delete(name)
				elsif category.eql? "armour"
					@armourProficiencies.delete(name)
				elsif category.eql? "tool"
					@toolProficiencies.delete(name)
				elsif category.eql? "language"
					@languages.delete(name)
				elsif category.eql? "expertise"
					@expertise.delete(name)
				else
					return "#{category} is not a valid category"
				end
				return "Proficiency removed"
			rescue
				return "Removing proficiency did not execute properly, not sure why, probably not good"
			end
		end

		def listProficiencies
			begin
				return <<~HEREDOC
					**Skills:** #{@skills.empty?? 'None' : @skills.join(', ')}\n
					**Saving Throws:** #{@saves.empty?? 'None' : @saves.join(', ')}\n
					**Weapons:** #{@weaponProficiencies.empty?? 'None' : @weaponProficiencies.join(', ')}\n
					**Armour:** #{@armourProficiencies.empty?? 'None' : @armourProficiencies.join(', ')}\n
					**Tools:** #{@toolProficiencies.empty?? 'None' : @toolProficiencies.join(', ')}\n
					**Languages:** #{@languages.empty?? 'None' : @languages.join(', ')}\n
					**Expertise:** #{@expertise.empty?? 'None' : @expertise.join(', ')}"
				HEREDOC
			rescue
				return "List did not execute properly, uh oh"
			end
		end

end

# DEBUG:
playerHash = {
	# "_id": BSON::ObjectId('598ce7f187e04d19e0e6a65e'),
	"name": "Bardee",
	"fullName": "Chef Jean Bardee",
	"maxHealth": 38,
	"speed": 30,
	"spellcastingLevel": 5,
	"levels":[
		{
			"class": "Bard", 
			"subclass": "Cuisine",
			"level": 5,
			"hitdice": 8
		}#,{
		# 	"class":"Wizard",
		# 	"subclass": nil,
		# 	"level": 2,
		# 	"hitdice": 8
		# }
	],
	"race": "Half-Elf",
	"abilities": {
		"str": 10,
		"dex": 14,
		"con": 15,
		"int": 16,
		"wis": 12,
		"cha": 19
	},
	"skills": ["Arcana", "History", "Nature", "Perception", "Persuasion"],
	"savingThrows": ["dex", "cha"],
	"expertise": ["Sleight of Hand", "Performance"],
	"languages": ["Common", "Elvish", "Undercommon"],
	"features": []
}

# player = Player.new(Client[:characters].find({'name' : 'Bardee'}).first());
# player = Player.new(playerHash)

# puts player.skillModifier('Sleight of Hand');