# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

# start the measure
class SetRoofInsulationRValue < OpenStudio::Measure::ModelMeasure
  # define the name that a user will see
  def name
    return 'Set Roof Insulation R Value'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument insulation R-value
    roof_r = OpenStudio::Measure::OSArgument.makeDoubleArgument('roof_r', true)
    roof_r.setDisplayName('Roof Insulation R-value (ft^2*h*R/Btu)')
    roof_r.setDefaultValue(30.0)
    args << roof_r

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user input to variable
    roof_r = runner.getDoubleArgumentValue('roof_r', user_arguments)

    # set limit for minimum insulation. This is used to limit input and for inferring insulation layer in construction.
    min_expected_r_value_ip = 1 # ip units

    # check the R-value for reasonableness
    if (roof_r < 0) || (roof_r > 500)
      runner.registerError("The requested roof insulation R-value of #{roof_r} ft^2*h*R/Btu was above the measure limit.")
      return false
    elsif roof_r > 60
      runner.registerWarning("The requested roof insulation R-value of #{roof_r} ft^2*h*R/Btu is abnormally high.")
    elsif roof_r < min_expected_r_value_ip
      runner.registerWarning("The requested roof insulation R-value of #{roof_r} ft^2*h*R/Btu is abnormally low.")
    end


    # short def to make numbers pretty (converts 4125001.25641 to 4,125,001.26 or 4,125,001). The definition be called through this measure
    def neat_numbers(number, roundto = 2) # round to 0 or 2)
      if roundto == 2
        number = format '%.2f', number
      else
        number = number.round
      end
      # regex to add commas
      number.to_s.reverse.gsub(/([0-9]{3}(?=([0-9])))/, '\\1,').reverse
    end

    # helper to make it easier to do unit conversions on the fly
    def unit_helper(number, from_unit_string, to_unit_string)
      converted_number = OpenStudio.convert(OpenStudio::Quantity.new(number, OpenStudio.createUnit(from_unit_string).get), OpenStudio.createUnit(to_unit_string).get).get.value
    end

    # convert roof_r to si for future use
    r_value_si = unit_helper(roof_r, 'ft^2*h*R/Btu', 'm^2*K/W')

    # create an array of roofs and find range of starting construction R-value (not just insulation layer)
    surfaces = model.getSurfaces
    exterior_surfaces = []
    exterior_surface_constructions = []
    exterior_surface_construction_names = []
    roof_resistance = []
    surfaces.each do |surface|
      if (surface.outsideBoundaryCondition == 'Outdoors') && (surface.surfaceType == 'RoofCeiling')
        exterior_surfaces << surface
        roof_const = surface.construction.get
        # only add construction if it hasn't been added yet
        if !exterior_surface_construction_names.include?(roof_const.name.to_s)
          exterior_surface_constructions << roof_const.to_Construction.get
        end
        exterior_surface_construction_names << roof_const.name.to_s
        roof_resistance << 1 / roof_const.thermalConductance.to_f
      end
    end

    # nothing will be done if there are no exterior surfaces
    if exterior_surfaces.empty?
      runner.registerAsNotApplicable('Model does not have any roofs.')
      return true
    end

    # report strings for initial condition
    initial_string = []
    exterior_surface_constructions.uniq.each do |exterior_surface_construction|
      # unit conversion of roof insulation from SI units (M^2*K/W) to IP units (ft^2*h*R/Btu)
      initial_conductance_ip = unit_helper(1 / exterior_surface_construction.thermalConductance.to_f, 'm^2*K/W', 'ft^2*h*R/Btu')
      initial_string << "#{exterior_surface_construction.name} (R-#{(format '%.1f', initial_conductance_ip)})"
    end
    runner.registerInitialCondition("The building had #{initial_string.size} roof constructions: #{initial_string.sort.join(', ')}.")

    # hashes to track constructions and materials made by the measure, to avoid duplicates
    constructions_hash_old_new = {}
    constructions_hash_new_old = {} # used to get netArea of new construction objects of construction it replaced
    materials_hash = {}

    # array and counter for new constructions that are made, used for reporting final condition
    final_constructions_array = []

    # loop through all constructions and materials used on roofs, edit and clone
    exterior_surface_constructions.each do |exterior_surface_construction|
      construction_layers = exterior_surface_construction.layers
      max_thermal_resistance_material = ''
      max_thermal_resistance_material_index = ''
      materials_in_construction = construction_layers.map.with_index {|layer, i| {"name"=>layer.name.to_s,
                                                                                  "index"=>i,
                                                                                  "nomass"=>!layer.to_MasslessOpaqueMaterial.empty?,
                                                                                  "roof_r"=>layer.to_OpaqueMaterial.get.thermalResistance,
                                                                                  "mat"=>layer}}

      no_mass_materials = materials_in_construction.select {|mat| mat["nomass"] == true}
      # measure will select the no mass material with the highest r-value as the insulation layer
      # if no mass materials are present, the measure will select the material with the highest r-value per inch
      if !no_mass_materials.empty?
        thermal_resistance_values = no_mass_materials.map {|mat| mat["roof_r"]}
        max_mat_hash = no_mass_materials.select {|mat| mat["roof_r"] >= thermal_resistance_values.max}
      else
        thermal_resistance_per_thickness_values = materials_in_construction.map {|mat| mat["roof_r"] / mat["mat"].thickness}
        target_index = thermal_resistance_per_thickness_values.index(thermal_resistance_per_thickness_values.max)
        max_mat_hash = materials_in_construction.select {|mat| mat["index"] == target_index}
        thermal_resistance_values = materials_in_construction.map {|mat| mat["roof_r"]}
      end
      max_thermal_resistance_material = max_mat_hash[0]["mat"]
      max_thermal_resistance_material_index = max_mat_hash[0]["index"]
      max_thermal_resistance = max_thermal_resistance_material.to_OpaqueMaterial.get.thermalResistance

      if max_thermal_resistance <= unit_helper(min_expected_r_value_ip, 'ft^2*h*R/Btu', 'm^2*K/W')
        runner.registerWarning("Construction '#{exterior_surface_construction.name}' does not appear to have an insulation layer and was not altered.")
      elsif (max_thermal_resistance >= r_value_si) && !allow_reduction
        runner.registerInfo("The insulation layer of construction #{exterior_surface_construction.name} exceeds the requested R-Value. It was not altered.")
      else
        # clone the construction
        final_construction = exterior_surface_construction.clone(model)
        final_construction = final_construction.to_Construction.get
        final_construction.setName("#{exterior_surface_construction.name} adj roof insulation")
        final_constructions_array << final_construction

        # push to hashes
        constructions_hash_old_new[exterior_surface_construction.name.to_s] = final_construction
        constructions_hash_new_old[final_construction] = exterior_surface_construction # push the object to hash key vs. name

        # find already cloned insulation material and link to construction
        target_material = max_thermal_resistance_material
        found_material = false
        materials_hash.each do |orig, new|
          if target_material.name.to_s == orig
            new_material = new
            materials_hash[max_thermal_resistance_material.name.to_s] = new_material
            final_construction.eraseLayer(max_thermal_resistance_material_index)
            final_construction.insertLayer(max_thermal_resistance_material_index, new_material)
            found_material = true
          end
        end

        # clone and edit insulation material and link to construction
        if found_material == false
          new_material = max_thermal_resistance_material.clone(model)
          new_material = new_material.to_OpaqueMaterial.get
          new_material.setName("#{max_thermal_resistance_material.name}_R-value #{roof_r} (ft^2*h*R/Btu)")
          materials_hash[max_thermal_resistance_material.name.to_s] = new_material
          final_construction.eraseLayer(max_thermal_resistance_material_index)
          final_construction.insertLayer(max_thermal_resistance_material_index, new_material)
          runner.registerInfo("For construction'#{final_construction.name}', material'#{new_material.name}' was altered.")

          # edit insulation material
          new_material_matt = new_material.to_Material
          if !new_material_matt.empty?
            starting_thickness = new_material_matt.get.thickness
            target_thickness = starting_thickness * r_value_si / thermal_resistance_values.max
            final_thickness = new_material_matt.get.setThickness(target_thickness)
          end
          new_material_massless = new_material.to_MasslessOpaqueMaterial
          if !new_material_massless.empty?
            final_thermal_resistance = new_material_massless.get.setThermalResistance(r_value_si)
          end
          new_material_airgap = new_material.to_AirGap
          if !new_material_airgap.empty?
            final_thermal_resistance = new_material_airgap.get.setThermalResistance(r_value_si)
          end
        end
      end
    end

    # loop through construction sets used in the model
    default_construction_sets = model.getDefaultConstructionSets
    default_construction_sets.each do |default_construction_set|
      if default_construction_set.directUseCount > 0
        default_surface_const_set = default_construction_set.defaultExteriorSurfaceConstructions
        if !default_surface_const_set.empty?
          starting_construction = default_surface_const_set.get.roofCeilingConstruction

          # creating new default construction set
          new_default_construction_set = default_construction_set.clone(model)
          new_default_construction_set = new_default_construction_set.to_DefaultConstructionSet.get
          new_default_construction_set.setName("#{default_construction_set.name} adj roof insulation")

          # create new surface set and link to construction set
          new_default_surface_const_set = default_surface_const_set.get.clone(model)
          new_default_surface_const_set = new_default_surface_const_set.to_DefaultSurfaceConstructions.get
          new_default_surface_const_set.setName("#{default_surface_const_set.get.name} adj roof insulation")
          new_default_construction_set.setDefaultExteriorSurfaceConstructions(new_default_surface_const_set)

          # use the hash to find the proper construction and link to new_default_surface_const_set
          target_const = new_default_surface_const_set.roofCeilingConstruction
          if !target_const.empty?
            target_const = target_const.get.name.to_s
            found_const_flag = false
            constructions_hash_old_new.each do |orig, new|
              if target_const == orig
                final_construction = new
                new_default_surface_const_set.setRoofCeilingConstruction(final_construction)
                found_const_flag = true
              end
            end
            if found_const_flag == false # this should never happen but is just an extra test in case something goes wrong with the measure code
              runner.registerWarning("Measure couldn't find the construction named '#{target_const}' in the exterior surface hash.")
            end
          end

          # swap all uses of the old construction set for the new
          construction_set_sources = default_construction_set.sources
          construction_set_sources.each do |construction_set_source|
            building_source = construction_set_source.to_Building
            # if statement for each type of object than can use a DefaultConstructionSet
            if !building_source.empty?
              building_source = building_source.get
              building_source.setDefaultConstructionSet(new_default_construction_set)
            end
            building_story_source = construction_set_source.to_BuildingStory
            if !building_story_source.empty?
              building_story_source = building_story_source.get
              building_story_source.setDefaultConstructionSet(new_default_construction_set)
            end
            space_type_source = construction_set_source.to_SpaceType
            if !space_type_source.empty?
              space_type_source = space_type_source.get
              space_type_source.setDefaultConstructionSet(new_default_construction_set)
            end
            space_source = construction_set_source.to_Space
            if !space_source.empty?
              space_source = space_source.get
              space_source.setDefaultConstructionSet(new_default_construction_set)
            end
          end

        end
      end
    end

    # link cloned and edited constructions for surfaces with hard assigned constructions
    exterior_surfaces.each do |exterior_surface|
      if !exterior_surface.isConstructionDefaulted && !exterior_surface.construction.empty?

        # use the hash to find the proper construction and link to surface
        target_const = exterior_surface.construction
        if !target_const.empty?
          target_const = target_const.get.name.to_s
          constructions_hash_old_new.each do |orig, new|
            if target_const == orig
              final_construction = new
              exterior_surface.setConstruction(final_construction)
            end
          end
        end

      end
    end

    # report strings for final condition
    final_string = [] # not all exterior roof constructions, but only new ones made. If  roof didn't have insulation and was not altered we don't want to show it
    affected_area_si = 0
    final_constructions_array.each do |final_construction|
      # unit conversion of roof insulation from SI units (M^2*K/W) to IP units (ft^2*h*R/Btu)
      final_conductance_ip = unit_helper(1 / final_construction.thermalConductance.to_f, 'm^2*K/W', 'ft^2*h*R/Btu')
      final_string << "#{final_construction.name} (R-#{(format '%.1f', final_conductance_ip)})"
      affected_area_si += final_construction.getNetArea
    end

    # add not applicable test if there were exterior roof constructions but non of them were altered (already enough insulation or doesn't look like insulated wall)
    if affected_area_si == 0
      runner.registerAsNotApplicable('No roofs were altered.')
      return true
      # affected_area_ip = affected_area_si
    else
      # ip construction area for reporting
      affected_area_ip = unit_helper(affected_area_si, 'm^2', 'ft^2')
    end

    # report final condition
    runner.registerFinalCondition("The existing insulation for roofs was changed to R-#{roof_r}. This was applied to #{neat_numbers(affected_area_ip, 0)} (ft^2) across #{final_string.size} roof constructions: #{final_string.sort.join(', ')}.")

    return true
  end
end

# this allows the measure to be used by the application
SetRoofInsulationRValue.new.registerWithApplication
