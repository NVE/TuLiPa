## TuLiPa

TuLiPa is a modular framework for time parameterized linear programming problems for use in energy market modelling. From a market representation and time-series datasets, it builds, updates and solves energy market LP-problems for the chosen horizon and scenario. The framework gives the user flexibility to choose the desired degree of detail of the problem, and new model objects with more complex functionality can be added without having to alter the existing code. TuLiPa can make deterministic or stochastic LP-problems, which can be used as building blocks in more complex models.

This is a prototype to test out ideas and inspire the field. Feedback, ideas and contributions are welcome.

### Motivation:
This work is part of [NVE](https://www.nve.no/english/)'s research project called "Power market model in [Julia](https://julialang.org/)". The goal of this project is to make an algorithm for simulating the Northern European power market with high temporal resolution, detailed hydropower, uncertainty in weather, and using only open-source software. We want to find out if breaking up the problem into many smaller LP-problems, solving many of them deterministically and with open-source solvers, can give fast and good results. The algorithm we have in mind is a simulation model that clears the power market with some of the bids generated from price prognosis and storage valuation models. The simulation model uses a rolling horizon approach where the underlying models are solved for each step:
1.	Price prognosis models with different degrees of details (e.g. long-term deterministic aggregated power market model)
2.	Models for valuating storage capacity (e.g. medium- or short-term stochastic hydropower scheduling of individual watercourses based on prices from 1)
3.	Market clearing model (e.g. deterministic bid optimization, with part of the bids from 2)

This is just one example of an algorithm we can build with TULIPA as building blocks.

### Modular TuLiPa:
The above-mentioned algorithm will have a lot of LP-problems, so we want a general framework for building, updating and solving the LP-problems. A modular system gives users the flexibility to add model objects with new functionality, without having to adapt the existing code that builds, updates and solves the LP-problems. For the general framework we define abstract datatypes and generic functions that describe how the system works.

#### Time-series data:
The framework is built around time-series data. References to the time-series data are stored in the model objects and are used to update the LP-problem together with the chosen horizon, model year and weather scenario. This gives flexibility to run the model with the desired temporal resolution without having to adapt the dataset each time.

#### Solvers:
The general framework supports connecting to the desired optimization framework or solver. We have built one problem structure that connects to the [JuMP](https://github.com/jump-dev/JuMP.jl) framework and one that connects directly to the [HiGHS](https://github.com/jump-dev/HiGHS.jl) package.

#### Boundary conditions:
The framework supports having state variables and setting them with boundary conditions. This is important for storages, certain problem restrictions, and stochastic algorithms where the master- and sub-problems needs to be connected.

#### Power system representation:
Real world concepts like transmission lines, power plants, hydropower storages and demands etc. are stored as structs in a list. The type of the struct and its data fields (and their types) decide characteristics of the model objects and how they are included into the LP-problem. The model object list can be manipulated based on the user’s preferences. We can for example start with a very detailed power market representation and simplify it (aggregate areas, aggregate power plants, remove startup costs, remove short-term storage system etc.…) before we run the model. We present the five main model objects:

| Model object | Description | Example |
| :---: | --- | --- |
| **Flow** | Variable for each period in a Horizon. Can have traits like Capacity or Cost, and is connected to Balances through Arrows. | Production, hydro release, transmission |
| **Storage** | Variable for each period in a Horizon that represent storage level at the end of the period. Contributes to its Balance, and can have traits. | Hydro storage, battery, gas storage |
| **Balance** | Takes inputs and outputs of a Commodity from variables for each period in a Horizon. Can be a balance equation (with contributions from variables and constants (RHSTerms)) or an exogenous system that holds the Price of the Commodity (Flows that contributes will have an income or loss) | Power balance, water balance, gas balance |
| **Commodity** | Commodity in Balances. Has Horizon that the Balance inherits. | Power, hydro, gas, hydrogen |
| **Arrow** | Describes contribution of a Flow into a Balance. Has direction to determine intput or output, and parameters to convert the Flow into the Commodity of the Balance. | Energy equivalent of hydro power plant to convert m3 to kWh |

![image](https://user-images.githubusercontent.com/40186418/213677992-ab96494c-42ae-42b8-bdc8-2b2b94c7673f.png)

#### Get an overview of TuLiPa:
- src/TuLiPa.jl – gives an overview of the different parts of the framework
- src/abstracttypes.jl – the abstract problem types (and their general interfaces) are described here
- src/problem_jump.jl – description of how the LP-problem is built, updated, solved and results are queried.
- src/balance.jl - src/flow.jl - src/storage.jl - src/trait_arrow.jl – the main model objects that make up the real-world concepts and how they are connected (like power markets, power plants, demands and hydro storages)
- src/ - the rest of the source code is also commented

#### See also demos:
- demos/Demo 1 - Deterministic power market with dummy data
- demos/Demo 2 - Deterministic power market with detailed data
- demos/Demo 4 - Deterministic hydro
- demos/Demo 5 - Two-stage stochastic hydro
- demos/Demo 6 - Two-stage stochastic hydro with Benders decomposition

#### Possible improvements to TuLiPa:
See file "Possible improvements to TuLiPa"

#### Next steps for the simulation model we want to build with TuLiPa:
We have TuLiPa that can be used to make the underlying models, and we have our dataset for Europe and detailed Nordic hydropower.
We need to build the underlying models and run them on different processor cores (and have them communicate). This includes making a stochastic hydropower problem, making a framework for moving results between models, and deciding on settings in the algorithm and models.

### Why Julia:
Julia is a modern and growing language made for scientific computing. It has a flexible type-hierarchy which is perfect for our modular framework. Together with “multiple dispatch” it is easy to make a general framework that works for different concrete types and methods/functions. It also makes it easy to add new concrete types or methods without having to change much of the existing code. 
Keywords to Google are “multiple dispatch”, “dynamically typed” and “just-in-time compilation”

### Contact:
Julien Cabrol: jgrc@nve.no

Harald Endresen:
