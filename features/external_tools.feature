@integration @external-tools
Feature: External Tool Integration
  As a user
  I want to integrate with external tools
  So that I can extend the application's capabilities

  Background:
    Given the application is running

  @go3mf
  Scenario: Open file with go3mf
    Given a file is loaded
    When I press O
    Then the go3mf CLI tool should be launched
    And it should open with the current file
    And the command should be "go3mf build <file> --open"

  @go3mf
  Scenario: go3mf executable discovery
    When the application searches for go3mf
    Then it should check the following paths in order:
      | Path                      |
      | /usr/local/bin/go3mf      |
      | /opt/homebrew/bin/go3mf   |
      | ~/go/bin/go3mf            |
      | ~/.local/bin/go3mf        |
      | Shell PATH via 'which'    |

  @openscad
  Scenario: OpenSCAD executable discovery
    When the application searches for OpenSCAD
    Then it should check the following paths in order:
      | Path                                              |
      | /Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD |
      | /usr/local/bin/openscad                            |
      | /opt/homebrew/bin/openscad                         |
      | Shell PATH via 'which'                             |

  @openscad
  Scenario: Open file in OpenSCAD editor
    Given an OpenSCAD file is loaded
    When I press Cmd+E or select "Open in OpenSCAD" from Tools menu
    Then the .scad file should open in OpenSCAD.app
    And the user can edit the file in OpenSCAD
    And file watching should trigger a reload when the file is saved

  @openscad
  Scenario: Open in OpenSCAD disabled for non-SCAD files
    Given a non-OpenSCAD file is loaded (e.g., .stl or .3mf)
    Then the "Open in OpenSCAD" menu item should be disabled

  @openscad
  Scenario: OpenSCAD rendering
    Given an OpenSCAD file is loaded
    Then it should be rendered to a temporary STL file
    And the temporary file should be in /var/tmp/
    And the temporary file should be cleaned up after use

  @openscad
  Scenario: OpenSCAD dependency tracking
    Given an OpenSCAD file with include statements is loaded
    Then all included files should be tracked
    And changes to any included file should trigger a reload

  @openscad
  Scenario: OpenSCAD messages panel
    Given an OpenSCAD file is rendered
    When the OpenSCAD output contains warnings, deprecations, or echo statements
    Then a collapsible messages panel should appear in the bottom-right corner
    And the panel should show the message count
    And the panel should be expandable to show individual messages

  @openscad
  Scenario: OpenSCAD warning display
    Given an OpenSCAD file produces a warning like "WARNING: Can't open library"
    Then the warning should appear with an orange triangle icon
    And the "WARNING:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD deprecation display
    Given an OpenSCAD file produces a deprecation like "DEPRECATED: Variable names..."
    Then the deprecation should appear with a yellow clock icon
    And the "DEPRECATED:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD echo display
    Given an OpenSCAD file uses echo() statements like "ECHO: -53.6289"
    Then the echo output should appear with a cyan speech bubble icon
    And the "ECHO:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD error display
    Given an OpenSCAD file produces an error like "ERROR: Assertion failed"
    Then the error should appear with a red X circle icon
    And the "ERROR:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD trace display
    Given an OpenSCAD file produces a trace like "TRACE: called by 'align'"
    Then the trace should appear with a purple branch icon
    And the "TRACE:" prefix should be stripped from the display

  @openscad
  Scenario: Messages shown even on render failure
    Given an OpenSCAD file fails to render
    When the output contains ECHO, WARNING, ERROR, or TRACE messages
    Then the messages panel should still display all captured messages
    And this helps debug the issue that caused the render failure

  @openscad @2d
  Scenario: 2D OpenSCAD file rendering
    Given an OpenSCAD file containing only 2D geometry is loaded
    When the initial render fails with "Current top level object is not a 3D object"
    Then the file should be automatically re-rendered with linear_extrude
    And the 2D shapes should be extruded to 1mm height for visualization
    And the model should display successfully

  @openscad @2d
  Scenario: 2D OpenSCAD file with includes
    Given a 2D OpenSCAD file uses include or use statements
    When the file is rendered for 2D visualization
    Then the included dependencies should still be resolved
    And changes to included files should trigger reload
    And the 2D content from all files should be extruded together

  @openscad @colors
  Scenario: OpenSCAD color extraction
    Given an OpenSCAD file uses color() modules
    When the file is loaded
    Then colors should be automatically extracted using multi-pass rendering
    And each colored region should be rendered separately
    And triangles should be assigned their respective colors
    And the model should display with per-triangle colors

  @openscad @colors
  Scenario: Color extraction process
    Given an OpenSCAD file with multiple colors
    When GoSTL processes the file
    Then it should first convert the file to CSG format
    And extract unique colors by redefining color() to echo values
    And verify all geometry is wrapped in color() calls
    And render each color in parallel for efficiency
    And merge all colored triangles into a single model

  @openscad @colors
  Scenario: Fallback for uncolored geometry
    Given an OpenSCAD file has geometry not wrapped in color()
    When the file is loaded
    Then GoSTL should detect the uncolored geometry
    And fall back to standard (non-colored) rendering
    And the model should display using the selected material color

  @openscad @colors
  Scenario: Fallback for single color or white
    Given an OpenSCAD file uses only white or a single color
    When the file is loaded
    Then GoSTL should skip color extraction
    And use standard rendering for efficiency
    And the model should display using the selected material color

  @go3mf
  Scenario: go3mf YAML rendering
    Given a go3mf YAML configuration file is loaded
    Then it should be rendered to a temporary 3MF file via go3mf CLI
    And the command should be "go3mf build <file> -o <output.3mf>"
    And the resulting 3MF should be parsed and displayed
    And the temporary file should be cleaned up on reload

  @go3mf @multi-plate
  Scenario: go3mf YAML with multiple plates
    Given a go3mf YAML configuration produces a multi-plate 3MF
    When the file is loaded
    Then the plate selector panel should appear
    And all plates from the generated 3MF should be available
