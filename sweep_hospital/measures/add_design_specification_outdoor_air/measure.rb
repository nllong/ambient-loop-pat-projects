# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class AddDesignSpecificationOutdoorAir < OpenStudio::Measure::ModelMeasure

  # human readable name
  def name
    return "Add Design Specification Outdoor Air"
  end

  # human readable description
  def description
    return "This measure sets a design specification outdoor air for the user-specified space type, and if the option to do so is selected by the user, also sets the AHU serving that space type to 100% outdoor air. "
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measure sets a design specification outdoor air for the user-specified space type, and, if the option to do so is selected by the user, also sets the AHU serving that space type to 100% outdoor air. It also sets economizer settings that will be used to determine when a heat recovery system is bypassed."
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
    
     # make a choice argument for space type
    space_type = OpenStudio::Measure::OSArgument.makeStringArgument("space_type", false)
    space_type.setDisplayName('Apply the Measure to this Space Type.')
    space_type.setDefaultValue('Hospital Lab - 90.1-2010 - 90.1-2010 - 90.1-2010') # lab space type
    args << space_type
    
    #Make an argument for the designed ventilation flow rate (in ACH)
    
    flow_rate = OpenStudio::Measure::OSArgument.makeDoubleArgument("flow_rate", true)
    flow_rate.setDisplayName('Desired OA Flow Rate Specification, in ACH')
    flow_rate.setDefaultValue(6.0)
    args << flow_rate
    
    #Make an argument for the user to select whether or not the space type's air loop should be set to 100% outdoor air. If so, the measure will select any air loop that serves spaces of that type and set it to 100% OA.
    set_OA = OpenStudio::Measure::OSArgument.makeBoolArgument('set_OA', true)
    set_OA.setDisplayName('Set AHU Serving Specified Space Type to 100% OA')
    set_OA.setDescription('This will set any AHU serving a space of the specified type to 100% outdoor air.')
    set_OA.setDefaultValue(true)
    args << set_OA
    
    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # # use the built-in error checking
    # if !runner.validateUserArguments(arguments(model), user_arguments)
      # return false
    # end

    # assign the user inputs to variables
    space_type = runner.getStringArgumentValue("space_type", user_arguments)
    flow_rate = runner.getDoubleArgumentValue("flow_rate", user_arguments)
    set_OA=runner.getBoolArgumentValue("set_OA", user_arguments)
    puts flow_rate 

    # # check the space_name for reasonableness
    # if space_name.empty?
      # runner.registerError("Empty space name was entered.")
      # return false
    # end

    # report initial condition of model
    runner.registerInitialCondition("The building started with #{model.getSpaces.size} spaces.")
    
    #Define measure to change OA specification object. 

   design_spec_outdoor_air_objects = model.getDesignSpecificationOutdoorAirs
    # TODO: - it would be nice to give ranges for different calculation methods but would take some work.

    # counters needed for measure
    altered_instances = 0

    # reporting initial condition of model
    if !design_spec_outdoor_air_objects.empty?
      runner.registerInitialCondition("The initial model contained #{design_spec_outdoor_air_objects.size} design specification outdoor air objects.")
    else
      runner.registerInitialCondition('The initial model did not contain any design specification outdoor air.')
    end

    # get space types in model
    building = model.building.get
    # if apply_to_building
      # space_types = model.getSpaceTypes
      # affected_area_si = building.floorArea
    # else
      space_types = []
      model.getSpaceTypes.each do |spacetype| 
      if spacetype.name.to_s == space_type
      space_types << spacetype # only run on a single space type
      puts space_types
      puts "in if statement"       
      # affected_area_si = space_type.floorArea
      end 
    end
    

    # split apart any shared uses of design specification outdoor air
    design_spec_outdoor_air_objects.each do |design_spec_outdoor_air_object|
      direct_use_count = design_spec_outdoor_air_object.directUseCount
      next if direct_use_count <= 1
      direct_uses = design_spec_outdoor_air_object.sources
      original_cloned = false

      # adjust count test for direct uses that are component data
      direct_uses.each do |direct_use|
        component_data_source = direct_use.to_ComponentData
        if !component_data_source.empty?
          direct_use_count -= 1
        end
      end
      next if direct_use_count <= 1

      direct_uses.each do |direct_use|
        # clone and hookup design spec OA
        space_type_source = direct_use.to_SpaceType
        if !space_type_source.empty?
          space_type_source = space_type_source.get
          cloned_object = design_spec_outdoor_air_object.clone
          space_type_source.setDesignSpecificationOutdoorAir(cloned_object.to_DesignSpecificationOutdoorAir.get)
          original_cloned = true
        end

        space_source = direct_use.to_Space
        if !space_source.empty?
          space_source = space_source.get
          cloned_object = design_spec_outdoor_air_object.clone
          space_source.setDesignSpecificationOutdoorAir(cloned_object.to_DesignSpecificationOutdoorAir.get)
          original_cloned = true
        end
      end

      # delete the now unused design spec OA
      if original_cloned
        runner.registerInfo("Making shared object #{design_spec_outdoor_air_object.name} unique.")
        design_spec_outdoor_air_object.remove
      end
    end

    # def to alter performance and life cycle costs of objects
    def alter_performance(object, flow_rate, runner)
      # edit instance based on percentage reduction
      instance = object

      # not checking if fields are empty because these are optional like values for space infiltration are.
      # new_outdoor_air_per_person = instance.setOutdoorAirFlowperPerson(instance.outdoorAirFlowperPerson - instance.outdoorAirFlowperPerson * design_spec_outdoor_air_reduction_percent * 0.01)
      new_outdoor_air_per_floor_area = instance.setOutdoorAirFlowperFloorArea(0)
      new_outdoor_air_ach = instance.setOutdoorAirFlowAirChangesperHour(flow_rate)
      # new_outdoor_air_rate = instance.setOutdoorAirFlowRate(instance.outdoorAirFlowRate - instance.outdoorAirFlowRate * design_spec_outdoor_air_reduction_percent * 0.01)
    end

    # array of instances to change
    instances_array = []

    # loop through space types
    space_types.each do |space_type|
      next if space_type.spaces.size <= 0
      instances_array << space_type.designSpecificationOutdoorAir
    end
    
     spaces=space_types #Added by AA, 7/18

    # get spaces in model
    # if apply_to_building
      # spaces = model.getSpaces
    # # else
      # if !space_type.spaces.empty?
        # spaces = space_types.spaces # only run on a single space type. 
      # end
    # # end

    spaces.each do |space|
      instances_array << space.designSpecificationOutdoorAir
    end

    instance_processed = []

    instances_array.each do |instance|
      next if instance.empty?
      instance = instance.get

      # only continue if this instance has not been processed yet
      next if instance_processed.include? instance
      instance_processed << instance

      # call def to alter performance and life cycle costs
      alter_performance(instance, flow_rate, runner)

      # rename
      # updated_instance_name = instance.setName("#{instance.name} (#{design_spec_outdoor_air_reduction_percent} percent reduction)")
      altered_instances += 1
    end

    if altered_instances == 0
      runner.registerAsNotApplicable('No design specification outdoor air objects were found in the specified space type(s).')
    end
    
     #If option selected by the user, set any air loops serving spaces of that type to 100% OA. 
     if set_OA == true 
     air_loop_mod=0
       model.getAirLoopHVACs.each do |airloop|
         airloop.thermalZones.each do |zone|
         zone.spaces.each do |space|
         spacetype = space.spaceType 
         if !spacetype.empty?
              spacetype=spacetype.get
              if spacetype.name.get.to_s == space_type 
              unless air_loop_mod >= 1
              oasys=airloop.airLoopHVACOutdoorAirSystem.get
              oa_cont=oasys.getControllerOutdoorAir
              #Set economizer settings which will be used to determine bypass for a heat recovery system. 
              oa_cont.setEconomizerControlType("DifferentialDryBulb")
              oa_cont.setMinimumLimitType("MinimumFlowWithBypass")
              oa_cont.setEconomizerMinimumLimitDryBulbTemperature(18.3) #65F
              oa_cont.setEconomizerMaximumLimitDryBulbTemperature(21.1)  #70F 
              oa_cont.setLockoutType("NoLockout") 
              oa_cont.setEconomizerControlActionType("MinimumFlowWithBypass")
              oa_cont.setMinimumFractionofOutdoorAirSchedule(model.alwaysOnDiscreteSchedule)
              air_loop_mod = 1 
        end
        end 
        end 
        end
        end 
        end 
        end 
       
    
    

    # # report final condition
    # affected_area_ip = OpenStudio.convert(affected_area_si, 'm^2', 'ft^2').get
    # runner.registerFinalCondition("#{altered_instances} design specification outdoor air objects in the model were altered affecting #{neat_numbers(affected_area_ip, 0)}(ft^2).")

    return true
  end
end
 

# register the measure to be used by the application
AddDesignSpecificationOutdoorAir.new.registerWithApplication
