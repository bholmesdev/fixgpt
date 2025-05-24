import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// void main() {
//   runApp(MyApp());
// }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Namer App',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.greenAccent),
        ),
        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var randomWordPair = WordPair.random();
  var favoriteWordPairs = <WordPair>{};

  bool isFavorited() {
    print(favoriteWordPairs);
    return favoriteWordPairs.contains(randomWordPair);
  }

  void toggleFavorite() {
    if (!favoriteWordPairs.contains(randomWordPair)) {
      favoriteWordPairs.add(randomWordPair);
    } else {
      favoriteWordPairs.remove(randomWordPair);
    }
    notifyListeners();
  }

  void getNext() {
    randomWordPair = WordPair.random();
    notifyListeners();
  }
}

class MyHomePage extends StatefulWidget {
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

// Adding an _ means `private`
class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = GeneratorPage();
      case 1:
        page = FavoritesPage();
      default:
        throw UnimplementedError("No widget at $selectedIndex");
    }
    return LayoutBuilder(builder: (context, constraints) {
      return Scaffold(
        body: Row(
          children: [
            // Prevent iOS notch or status bars from covering the UI
            SafeArea(
              child: NavigationRail(
                extended: constraints.maxWidth >= 600,
                destinations: [
                  NavigationRailDestination(
                    icon: Icon(Icons.home),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.favorite),
                    label: Text('Favorites'),
                  ),
                ],
                selectedIndex: selectedIndex,
                onDestinationSelected: (value) {
                  // State mutation needs to be wrapped in `setState`.
                  // Weird the compiler lets you assign without this...
                  setState(() {
                    selectedIndex = value;
                  });
                },
              ),
            ),
            // Expanded = take remaining space. Greedy. flex 1
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: page,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class FavoritesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      body: SafeArea(
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ListView(children: [
          Text("Words", style: theme.textTheme.titleLarge),
          SizedBox(height: 8),
          for (var pair in appState.favoriteWordPairs)
            Align(
                alignment: Alignment.centerLeft,
                child: Text("${pair.first} ${pair.second}",
                    style: theme.textTheme.bodyLarge))
        ]),
      )),
    );
  }
}

class GeneratorPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var word = appState.randomWordPair;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Word(pair: word),
              SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FavoriteButton(appState: appState),
                  SizedBox(width: 10),
                  ElevatedButton(
                      onPressed: () {
                        appState.getNext();
                      },
                      child: Text("New word"))
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.appState,
  });

  final MyAppState appState;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(
          !appState.isFavorited() ? Icons.favorite_outline : Icons.favorite),
      label: Text("Like"),
      onPressed: () {
        appState.toggleFavorite();
      },
    );
  }
}

class Word extends StatelessWidget {
  const Word({
    super.key,
    required this.pair,
  });

  final WordPair pair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.displaySmall!.copyWith(
        color: theme.colorScheme.onPrimary,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
          color: theme.colorScheme.primary,
          elevation: 8.0,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
            child: Text(
              pair.asLowerCase,
              style: textStyle,
              semanticsLabel: "${pair.first} ${pair.second}",
            ),
          )),
    );
  }
}
