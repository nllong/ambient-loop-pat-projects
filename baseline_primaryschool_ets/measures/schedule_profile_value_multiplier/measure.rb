require File.dirname(__FILE__) + '/resources/rubystats/uniform_distribution.rb'
Uniform = Rubystats::UniformDistribution
require File.dirname(__FILE__) + '/resources/rubystats/normal_distribution.rb'
Normal = Rubystats::NormalDistribution
require File.dirname(__FILE__) + '/resources/triangular_distribution.rb'
include Enumerable

# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class ScheduleProfileValueMultiplier < OpenStudio::Measure::ModelMeasure

  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Schedule Profile Value Multiplier'
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
      # only include if schedule use count > 0
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
    schedule.setDisplayName('Schedule to Multiply the Values For.')
    schedule.setDefaultValue('*All Ruleset Schedules*') # if no schedule is chosen this will run on all air loops
    args << schedule

    # make an argument for distribution
    distributions = OpenStudio::StringVector.new
    distributions << 'Uniform'
    distributions << 'Normal'
    distributions << 'Triangular'
    dist = OpenStudio::Measure::OSArgument.makeChoiceArgument('dist', distributions,  true)
    dist.setDisplayName('Distribution for Random Shift Value Generator.')
    dist.setDefaultValue('Uniform')
    args << dist

    # make an argument for shift lower limit
    mult_ll = OpenStudio::Measure::OSArgument.makeDoubleArgument('mult_ll', true)
    mult_ll.setDisplayName('Schedule Profiles Values Multiplier Lower Limit.')
    mult_ll.setDefaultValue(1)
    args << mult_ll

    # make an argument for shift upper limit
    mult_ul = OpenStudio::Measure::OSArgument.makeDoubleArgument('mult_ul', true)
    mult_ul.setDisplayName('Schedule Profiles Values Multiplier Upper Limit.')
    mult_ul.setDefaultValue(2)
    args << mult_ul

    # make an argument for shift peak
    mult_ct = OpenStudio::Measure::OSArgument.makeDoubleArgument('mult_ct', false)
    mult_ct.setDisplayName('Schedule Values Multiplier Peak for Triangular Distribution.')
    args << mult_ct

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
    dist = runner.getStringArgumentValue('dist', user_arguments)
    mult_ll = runner.getDoubleArgumentValue('mult_ll', user_arguments)
    mult_ul = runner.getDoubleArgumentValue('mult_ul', user_arguments)
    mult_ct = runner.getDoubleArgumentValue('mult_ct', user_arguments)

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

    # randomly generate shift value
    if dist == 'Uniform'
      unif = Uniform.new(mult_ll, mult_ul)
      mult_value = unif.rng
    elsif dist == 'Normal'
      mu = (mult_ul - mult_ll) / 2 + mult_ll
      sigma = (mult_ul - mult_ll) / 6
      norm = Normal.new(mu, sigma)
      mult_value = norm.rng
    else
      mult_value = trirng(mult_ct, mult_ll, mult_ul)
    end

    # check shift value for reasonableness
    if (mult_value / 24) == (mult_value / 24).to_i
      runner.registerAsNotApplicable('No schedule value multiplier was requested, the model was not changed.')
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
      schedule.setName("#{schedule.name} - (Multiplied #{mult_value} units)")

      # give info messages as I change specific profiles
      runner.registerInfo("Adjusting #{schedule.name}")

      # edit profiles
      profiles.each do |day_sch|
        times = day_sch.times
        values = day_sch.values

        # arrays for values to avoid overlap conflict of times
        new_values = []

        # push values to array
        values.each do |value|
          new_values << value*mult_value
        end

        # clear values
        day_sch.clearValues

        # make new values
        for i in 0..(new_values.length - 1)
          day_sch.addValue(times[i], new_values[i])
        end
      end
    end

    # reporting final condition of model
    if apply_to_all_schedules
      runner.registerFinalCondition('Multiplied values for all profiles for all schedules.')
    else
      runner.registerFinalCondition("Multiplied values for all profiles used by #{schedule.name}.")
    end

    return true
  end
end

# register the measure to be used by the application
ScheduleProfileValueMultiplier.new.registerWithApplication
