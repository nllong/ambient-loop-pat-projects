# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class SetScheduleProfileStartEndTimes < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Set Schedule Profile Start End Times'
  end

  # human readable description
  def description
    return 'Expand or contract schedule profile by specifying new start and end times. The schedule profile shape is preserved.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Expand or contract schedule profile by specifying new start and end times. The schedule profile shape is preserved.'
  end

  # This method emulates the chunk_while method that exists in Ruby 2.6.1
  def chunk_schedule(data)
    if data.length == 1 || data.uniq.length == 1
      return data[0]
    else
      new_chunk = []
      new_array = []
      previous_value = nil
      data.each_with_index do |i, index|
        if index == 0
          new_array << i
          previous_value = i
          next
        elsif index == data.length-1
          new_chunk << new_array
        end
        if previous_value == i
          new_array << i
        else
          previous_value = i
          new_chunk << new_array
          new_array = []
          new_array << i
        end
      end
      return new_chunk
    end
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # populate choice argument for schedules that are applied to surfaces in the model
    schedule_handles = OpenStudio::StringVector.new
    schedule_display_names = OpenStudio::StringVector.new

    # putting space types and names into hash
    schedule_args = model.getScheduleRulesets
    schedule_args_hash = {}
    schedule_args.each do |schedule_arg|
      schedule_args_hash[schedule_arg.name.to_s] = schedule_arg
    end

    # looping through sorted hash of schedules
    schedule_args_hash.sort.map do |key, value|
      #only include if schedule use count > 0
      if value.directUseCount > 0
        schedule_handles << value.handle.to_s
        schedule_display_names << key
      end
    end

    # add building to string vector with air loops
    building = model.getBuilding
    schedule_handles << building.handle.to_s
    schedule_display_names << '*All Ruleset Schedules*'

    # make an argument for schedule
    schedule = OpenStudio::Measure::OSArgument.makeChoiceArgument('schedule', schedule_handles, schedule_display_names, true)
    schedule.setDisplayName('Schedule to Expand or Contract')
    schedule.setDefaultValue('*All Ruleset Schedules*') # if no schedule is chosen this will run on all air loops
    args << schedule

    # make an argument for schedule lower limit
    new_start = OpenStudio::Measure::OSArgument.makeIntegerArgument('new_start', true)
    new_start.setDisplayName('Schedule Start (hr)')
    new_start.setDefaultValue(8)
    args << new_start

    # make an argument for shift upper limit
    new_end = OpenStudio::Measure::OSArgument.makeIntegerArgument('new_end', true)
    new_end.setDisplayName('Schedule End (hr)')
    new_end.setDefaultValue(18)
    args << new_end

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    schedule = runner.getOptionalWorkspaceObjectChoiceValue('schedule', user_arguments, model)
    new_start = runner.getIntegerArgumentValue('new_start', user_arguments)
    new_end = runner.getIntegerArgumentValue('new_end', user_arguments)
    new_dur = new_end - new_start

    runner.registerInfo("The new schedule duration is #{new_dur}")

    # check the schedule for reasonableness
    apply_to_all_schedules = false
    if schedule.empty?
      handle = runner.getStringArgumentValue('schedule', user_arguments)
      if handle.empty?
        runner.registerError('No schedule was chosen.')
      else
        runner.registerError("The selected schedule with handle '#{handle}' was not found in the model. It may have been removed by another measure.")
      end
      return false
    else
      if !schedule.get.to_ScheduleRuleset.empty?
        schedule = schedule.get.to_ScheduleRuleset.get
      elsif !schedule.get.to_Building.empty?
        apply_to_all_schedules = true
      else
        runner.registerError('Script Error - argument not showing up as schedule.')
        return false
      end
    end

    # get schedules for measure
    schedules = []
    if apply_to_all_schedules
      raw_schedules = model.getScheduleRulesets
      raw_schedules.each do |raw_schedule|
        if raw_schedule.directUseCount > 0
          schedules << raw_schedule
        end
      end

    else
      schedules << schedule # only run on a single schedule
    end

    schedules.each do |schedule|
      # array of all profiles to change
      profiles = []

      # push default profiles to array
      default_rule = schedule.defaultDaySchedule
      profiles << default_rule

      # push profiles to array
      rules = schedule.scheduleRules
      rules.each do |rule|
        day_sch = rule.daySchedule
        profiles << day_sch
      end

      # add design days to array
      summer_design = schedule.summerDesignDaySchedule
      winter_design = schedule.winterDesignDaySchedule
      profiles << summer_design
      profiles << winter_design

      # reporting initial condition of model
      if apply_to_all_schedules
        runner.registerInitialCondition("#{schedules.size} schedules are used in this model.")
      else
        runner.registerInitialCondition("Schedule #{schedule.name} has #{profiles.size} profiles including design days.")
      end

      # rename schedule
      schedule.setName("#{schedule.name} Expanded or Contracted")

      # give info messages as I change specific profiles
      runner.registerInfo("Adjusting #{schedule.name}")

      # edit profiles
      profiles.each do |day_sch|
        old_times = day_sch.times
        old_values = day_sch.values

        old_start = []
        for i in 0..(old_values.length - 1)
          if i == (old_values.length - 1)
            old_start = OpenStudio::Time.new(0, 0, 0, 0)
            next
          end
          if old_values[i] <= 0.01 && old_values[i+1] > 0.01
            old_start << old_times[i+1]
            if old_start.length > 1
              old_start = old_start.min
            end
          end
        end
        old_start = old_start::hours

        runner.registerInfo("Cupcake #{old_start}")

        old_end = []
        for i in 0..(old_values.length - 1)
          if i == (old_values.length - 1)
            old_end = old_times[0]
            next
          end
          if old_values[i] <= 0.01 && old_values[i-1] > 0.01
            old_end << old_times[i-1]
            if old_end.length > 1
              old_end = old_end.max
            end
          end
        end
        old_end = old_end::hours


        old_sch = old_values[old_start..old_end]
        old_dur = old_sch.length

        chunked = chunk_schedule(old_sch)

        # you can update to the method below once OS supports ruby 2.5.1
        #chunked = old_sch.chunk_while {|i,j| i == j}.to_a

        # clear old_values
        day_sch.clearValues

        # reorganize schedule based on specified start and end points
        if chunked.class == Float
          for i in new_start..new_end
            day_sch.addValue(OpenStudio::Time.new(0,i, 0, 0), chunked) # add new values
          end
        else
          chunk_values = []
          percentage = []
          for chunk in chunked
            percentage << chunk.length/old_dur.to_f
            chunk_values << chunk[0]
          end
          nhrs = []
          for p in percentage
            nhrs << (p*new_dur).round # calculate number of hours for each value
          end
          new_values = []
          for i in 0..(chunk_values.length-1)
            new_values = new_values + Array.new(nhrs[i], chunk_values[i]) # create new value array
          end
          for i in new_start..(new_start+new_values.length-1)
            day_sch.addValue(OpenStudio::Time.new(0, i, 0, 0), new_values[i-new_start]) # add new values
          end
        end

      end
    end

    # reporting final condition of model
    runner.registerFinalCondition('Expanded or contracted profiles for all schedules.')

    return true
  end
end

# this allows the measure to be use by the application
SetScheduleProfileStartEndTimes.new.registerWithApplication