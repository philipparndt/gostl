@material
Feature: Material System
  As a user
  I want to select different materials
  So that I can visualize the model with accurate colors and calculate weight

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Default material is PLA
    When a model is first loaded
    Then the default material should be PLA
    And the model should be displayed with PLA color properties

  Scenario: Cycle material with keyboard
    When I press Cmd+M
    Then the material should cycle to the next type
    And the cycle order should be: PLA -> ABS -> PETG -> TPU -> Nylon -> PLA

  Scenario: PLA material properties
    When I select PLA material
    Then the model should be displayed with blue-gray color (0.5, 0.6, 0.9)
    And the material density should be 1.24 g/cm³
    And the material should appear matte (glossiness 0.0)

  Scenario: ABS material properties
    When I select ABS material
    Then the model should be displayed with warm gray color (0.85, 0.85, 0.8)
    And the material density should be 1.04 g/cm³
    And the material should have slight gloss (glossiness 0.3)

  Scenario: PETG material properties
    When I select PETG material
    Then the model should be displayed with blue-tinted color (0.88, 0.92, 0.98)
    And the material density should be 1.27 g/cm³
    And the material should appear glossy (glossiness 0.8)

  Scenario: TPU material properties
    When I select TPU material
    Then the model should be displayed with dark gray color (0.75, 0.75, 0.8)
    And the material density should be 1.21 g/cm³
    And the material should appear very matte (glossiness 0.1)

  Scenario: Nylon material properties
    When I select Nylon material
    Then the model should be displayed with cream/beige color (0.95, 0.93, 0.88)
    And the material density should be 1.14 g/cm³
    And the material should have moderate gloss (glossiness 0.4)

  Scenario: Weight calculation
    Given I have a model with known volume
    When a material is selected
    Then the weight should be calculated using the formula: Volume (mm³) / 1000 × Density (g/cm³)
    And the weight should be displayed in the info panel

  Scenario: Weight display formatting - grams
    Given the calculated weight is less than 1 kilogram
    Then the weight should be displayed in grams
    And the format should include one decimal place (e.g., "234.5 g")

  Scenario: Weight display formatting - kilograms
    Given the calculated weight is 1 kilogram or more
    Then the weight should be displayed in kilograms
    And the format should include two decimal places (e.g., "1.23 kg")

  Scenario: Material preserved on file reload
    Given I have selected a specific material
    When the file is auto-reloaded
    Then the selected material should remain unchanged
    And the weight should be recalculated with the current model volume

  Scenario: Material change from menu
    When I select "Change Material" from the Tools menu
    Then the material should cycle to the next type
    And this should be equivalent to pressing Cmd+M
