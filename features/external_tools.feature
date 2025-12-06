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
