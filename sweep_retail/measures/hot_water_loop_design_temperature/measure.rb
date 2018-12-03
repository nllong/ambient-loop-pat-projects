# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class HotWaterLoopDesignTemperature < OpenStudio::Ruleset::ModelUserScript

  # human readable name
  def name
    return "Hot Water Loop Design Temperature"
  end

  # human readable description
  def description
    return "Set the design temperature of the Hot Water Loop to the specified value."
  end

  # human readable description of modeling approach
  def modeler_description
    return "The name of the loop must be 'Hot Water Loop'"
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # the name of the space to add to the model
    temp = OpenStudio::Ruleset::OSArgument.makeDoubleArgument("hot_water_temperature", true)
    temp.setDisplayName("Hot Water Temperature")
    temp.setDescription("Design temperature of the hot water loop. Name must be Hot Water Loop")
    args << temp

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
    temp = runner.getDoubleArgumentValue("hot_water_temperature", user_arguments)

    # get the hot water loop
    # This measure only works with the predifined loop name of `Ambient Loop`
    plant_loop = model.getPlantLoopByName('Ambient Loop').get

    # try and set the temperature of the ambient loop - this includes setting the
    # plant loop min/max temperatures, the sizing plant objects, and the schedules
    loop_sizing = plant_loop.sizingPlant

    # report initial condition of model
    runner.registerInitialCondition("Hot water loop design temperature started with #{loop_sizing.designLoopExitTemperature}")

    loop_sizing.setDesignLoopExitTemperature(temp)

    # report final condition of model
    runner.registerFinalCondition("Hot water loop design temperature ended with #{loop_sizing.designLoopExitTemperature}")

    return true
  end
end

# register the measure to be used by the application
HotWaterLoopDesignTemperature.new.registerWithApplication
