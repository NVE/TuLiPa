## TuLiPa

TuLiPa is a modular and extensible system for working with linear programming (LP) problems for use in energy market modelling. From a market representation and time-series datasets, it creates, updates and solves energy market LP problems for the chosen horizon and scenario. The system gives the user flexibility to choose the desired degree of detail of the problems, and new model objects with more complex functionality can be added without having to alter the existing code. TuLiPa can make deterministic or stochastic LP problems, which can be used as building blocks in more complex models.

This is a prototype to test out ideas and inspire the field. Feedback, ideas and contributions are welcome.

### Motivation:
With the transition towards a renewable-based power system, we need models that can represent the new technologies, markets and dynamics. One of [NVE](https://www.nve.no/english/)’s initiatives to improve our understanding of power market modelling, is the ongoing research project called “Power market modelling in Julia”. The goal of this project is to test a new fundamental energy market model for operational planning. The model should be able to simulate the Northern European power market with high temporal resolution, detailed hydropower (or any other technology), uncertainty in weather, and using only open-source software. We want to find out if decomposing the complex power market problem into many smaller subproblems, solving many of them deterministically and with open-source solvers, can give fast and good results. The simulation concept is inspired by how power dispatch is planned in real life, with longer term price prognosis, calculation of individual storage values (e.g. water, battery or gas storage values) with different models for different technologies, and at the end a market clearing algorithm that takes all the details into account. These ideas are implemented in the fundamental energy market simulation model for operational planning, [JulES](https://github.com/NVE/JulES/).

The above-mentioned algorithm (JulES) will have a lot of similar LP problems and model objects that represent the power system. We therefore want a general system for building, updating and solving the LP-problems. We therefore make TuLiPa.

### Modular TuLiPa:
A modular system gives users the flexibility to add model objects with new functionality, without having to adapt the existing code that builds, updates and solves the LP-problems. For the general framework we define abstract datatypes and generic functions that describe how the system works. A modular framework facilitates further development of TuLiPa and the power market models built on it.

#### Power system representation:
Real world concepts like transmission lines, power plants, hydropower storages and demands etc. are stored as structs in a list. The type of the struct and its data fields (and their types) decide characteristics of the model objects and how they are included into the LP-problem. The model object list can be manipulated based on the user’s preferences. We can for example start with a very detailed power market representation and simplify it (aggregate areas, aggregate power plants, aggregate watercourses, remove startup costs, remove short-term storage system etc.…) before we run the model. We present the five main model objects:

| Model object | Description | Example |
| :---: | --- | --- |
| **Flow** | Variable for each period in a Horizon. Can have traits like Capacity or Cost, and is connected to Balances through Arrows. | Production, hydro release, transmission |
| **Storage** | Variable for each period in a Horizon that represent storage level at the end of the period. Contributes to its Balance, and can have traits. | Hydro storage, battery, gas storage |
| **Balance** | Takes inputs and outputs of a Commodity from variables for each period in a Horizon. Can be a balance equation (with contributions from variables and constants (RHSTerms)) or an exogenous system that holds the Price of the Commodity (Flows that contributes will have an income or loss) | Power balance, water balance, gas balance |
| **Commodity** | Commodity in Balances. Has Horizon that the Balance inherits. | Power, hydro, gas, hydrogen |
| **Arrow** | Describes contribution of a Flow into a Balance. Has direction to determine intput or output, and parameters to convert the Flow into the Commodity of the Balance. | Energy equivalent of hydro power plant to convert m3 to kWh |

![image](https://user-images.githubusercontent.com/40186418/213677992-ab96494c-42ae-42b8-bdc8-2b2b94c7673f.png)

### Input system:
The model objects have a complicated nested structure which works well for LP problems. However, we found it too complicated to be used by end users to create datasets. We wanted an input system that was extensible, composable and modular, and this suggested to use a flat structure instead of a nested one. Inputs are therefore a list of data elements and have these nice properties:
* Easy to port datasets from other sources. Since data elements are small and use references to other data elements, it is usually a matter of looping over objects in the source, create needed data elements and add them as you go.
* Easy to store dataset in replaceable parts. E.g. have different hydropower datasets with different aggregation levels. E.g. have exogeneous or endogenous represenation of the continental power system.
* Easy to add functionality. E.g. give an existing Flow element SoftBound constraint by adding SoftBound data elements referring to the Flow element. E.g. replace BaseArrow with SegmentedArrow to model PQ-curves for an existing Flow element.

#### Time:
- The problem time can consider two dimensions; weather scenarios and model years (e.g. power system in 2030, 2040 or 2050).
- The framework is built around time-series data. References to the time-series data are stored in the model objects and are used to update the LP-problem together with the chosen horizon and problem time. Time series data gives flexibility to run the model with the desired temporal resolution without having to adapt the dataset each time.
- There are different types of horizons / time resolutions that can be used in the models. Different model objects can also have different horizons in the same model. We have implemented SequentialHorizon, AdaptiveHorizon and ShrinkableHorizon:
  - SequentialHorizon represents periods with a list of (N, timedelta) pairs. Can represent for example hourly or weekly time resolution.
  - AdaptiveHorizon can include more details with less periods, while still keeping a sequential structure. It has an overlying dimension with sequential periods, while in the second dimension hours (or time periods) are grouped into load blocks based on their characteristics (e.g. hours with similar residual load).
  - In a ShrinkableHorizon the horizon duration shrinks (to a point, and then resets) between simulation steps, while the number of periods stays the same. This improves the update and solve time of the problem since we can reuse values between simulation steps. 
- We can use one scenario at the start of the problem, and one at the end. Also with a smooth transition, which can be used to phase in uncertainty.
- It is possible to build in support for time delays in for example waterways.

#### Solvers:
The general framework supports connecting to the desired optimization framework or solver. We have built one problem structure that connects to the [JuMP](https://github.com/jump-dev/JuMP.jl) framework, one that connects directly to the [HiGHS](https://github.com/jump-dev/HiGHS.jl) package, and one that connects directly to the [CPLEX](https://github.com/jump-dev/CPLEX.jl) package.

#### Boundary conditions:
The framework supports having state variables and setting them with boundary conditions. This is important for storages, certain problem restrictions, and stochastic algorithms where the master- and sub-problems needs to be connected. We have built model objects for start state, end values and Benders cuts.

#### Get an overview of TuLiPa:
- src/TuLiPa.jl – gives an overview of the different parts of the framework
- src/abstracttypes.jl – the abstract problem types (and their general interfaces) are described here
- src/problem_jump.jl – description of how the LP-problem is built, updated, solved and results are queried.
- src/balance.jl - src/flow.jl - src/storage.jl - src/trait_arrow.jl – the main model objects that make up the real-world concepts and how they are connected (like power markets, power plants, demands and hydro storages)
- src/horizons.jl - src/horizons_shrinkable_shiftable.jl - the horizons that represent the time resolution in the problems
- src/input_system.jl - description of the input system in TuLiPa
- src/ - the rest of the source code is also commented

#### See also demos (&#x2714; = open data so you can run it yourself):
- demos/Demo 1 - Deterministic power market with dummy data :heavy_check_mark:
- demos/Demo 2 - Deterministic power market with detailed data
- demos/Demo 4 - Deterministic hydro :heavy_check_mark:
- demos/Demo 5 - Two-stage stochastic hydro :heavy_check_mark:
- demos/Demo 6 - Two-stage stochastic hydro with Benders decomposition :heavy_check_mark:
- [JulES, an energy market simulation model that uses TuLiPa as building blocks](https://github.com/NVE/JulES/)
  - JulES/demos/Demo JulES as a solar with battery model :heavy_check_mark:
  - JulES/demos/Demo JulES as a single watercourse model :heavy_check_mark:
  - JulES/demos/Demo JulES as a long-term series simulation model
  - JulES/demos/Demo JulES as a medium-term parallel prognosis model

### Setup
*  Install julia version 1.9.2:
https://julialang.org/downloads/
* Clone repository
```console
git clone https://github.com/NVE/TuLiPa.git
``` 

Enter the folder with project.toml using a terminal window and run Julia and these commands:

With julia prompt change to Julias Pkg mode using ] and enter

```console
Julia> ]
```
With pkg prompt and while being inside the project folder, activate the project
```console
(@v1.9) pkg> activate .
```

Prompts shows the project is activated, then installs the libraries needed with instantiate
```console
(TuLiPa) pkg> instantiate
```

To start running the demos, run jupyter notebook from the terminal while being inside the TuLiPa project folder (make sure the kernel is julia 1.9.2)
```console
jupyter notebook 
```

If jupyter is not installed then it can be installed using IJulia
```console
Julia> using IJulia
Julia> IJulia.notebook()
```

### Why Julia:
Julia is a modern and growing language made for scientific computing. It has a flexible type-hierarchy which is perfect for our modular framework. Together with “multiple dispatch” it is easy to make a general framework that works for different concrete types and methods/functions. It also makes it easy to add new concrete types or methods without having to change much of the existing code. 
Keywords to Google are “multiple dispatch”, “dynamically typed” and “just-in-time compilation”

### Contact:
Julien Cabrol: jgrc@nve.no

Harald Endresen Haukeli: haen@nve.no

### Licensing:
Copyright 2023 The Norwegian Water Resources and Energy Directorate, and contributors.

TuLiPa is a free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 3 of the License, or (at your
option) any later version.

TuLiPa is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public License
along with TuLiPa; see the file COPYING.LESSER.  If not, see
http://www.gnu.org/licenses/ or write to the Free Software Foundation, Inc.,
51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
