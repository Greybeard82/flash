/// The optional set of feeds offered during onboarding, and from either empty
/// state afterwards.
///
/// Plain consts rather than a bundled asset: this is a fixed list of fifteen
/// entries that has to be readable by a unit test without a Flutter binding,
/// and loading it through `rootBundle` would buy nothing but an async gap and
/// a second place for it to be wrong.
///
/// Category *display names* are deliberately not here — they are ARB keys
/// (`starterCategoryWorldNews` and friends) resolved at seeding time, because
/// a folder created for a German user should be called "Weltnachrichten". Once
/// created, the folder name is ordinary user data and is never re-translated.
///
/// Every feed in this list is verified to produce articles through Flash's own
/// fetch pipeline by `test/starter_pack_live_test.dart`, which is the gate
/// that matters: a feed that parses but publishes nothing inside the 7-day
/// fetch window seeds a category that looks broken.
library;

class StarterFeed {
  /// The name the feed is stored under. Taken from this list rather than from
  /// the feed's own `<title>`, so the picker's subtitle and the row the user
  /// ends up with say the same thing.
  final String title;
  final String url;
  final String siteUrl;
  final String description;

  const StarterFeed({
    required this.title,
    required this.url,
    required this.siteUrl,
    required this.description,
  });
}

class StarterCategory {
  /// Stable identifier. Used as the picker's selection key and to look the
  /// localised folder name up; never shown and never stored.
  final String id;
  final List<StarterFeed> feeds;

  const StarterCategory({required this.id, required this.feeds});
}

/// The categories that deliberately ship with a single feed.
///
/// The rule everywhere else is two or more, so that one publisher going quiet
/// cannot empty a category — which is the exact failure that got the app
/// pulled. These two are exceptions David took knowingly on 11 Sep 2026, after
/// the live gate found no second feed that clears the 7-day fetch window:
/// every fitness candidate 404s, and every travel blog publishes too slowly.
/// An entry here is a statement that the thinness is known, not an oversight —
/// remove it the moment a second feed is added.
const Set<String> kSingleFeedStarterCategories = {'fitness_health', 'travel'};

/// Display order, for the categories and for the feeds inside each one.
const List<StarterCategory> kStarterPack = [
  StarterCategory(
    id: 'world_news',
    feeds: [
      StarterFeed(
        title: 'BBC News (World)',
        url: 'https://feeds.bbci.co.uk/news/world/rss.xml',
        siteUrl: 'https://www.bbc.com/news/world',
        description: 'Breaking global events, geopolitical analysis, and '
            'regional coverage across all continents.',
      ),
      StarterFeed(
        title: 'The Guardian (World)',
        url: 'https://www.theguardian.com/world/rss',
        siteUrl: 'https://www.theguardian.com/world',
        description: 'International news, climate reporting, political '
            'commentary, and long-form global investigations.',
      ),
      StarterFeed(
        title: 'The New York Times (World)',
        url: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
        siteUrl: 'https://www.nytimes.com',
        description: 'Top international reporting, foreign policy shifts, and '
            'investigative global journalism.',
      ),
    ],
  ),
  StarterCategory(
    id: 'tech',
    feeds: [
      StarterFeed(
        title: 'Ars Technica',
        url: 'https://feeds.arstechnica.com/arstechnica/index',
        siteUrl: 'https://arstechnica.com',
        description: 'In-depth technical analysis, hardware, AI developments, '
            'tech policy, and scientific research.',
      ),
      StarterFeed(
        title: 'The Verge',
        url: 'https://www.theverge.com/rss/index.xml',
        siteUrl: 'https://www.theverge.com',
        description: 'Consumer tech, gadget launches, software updates, and '
            'platform ecosystem shifts.',
      ),
      StarterFeed(
        title: 'WIRED',
        url: 'https://www.wired.com/feed/rss',
        siteUrl: 'https://www.wired.com',
        description: 'Intersection of technology, cybersecurity, culture, '
            'science, and long-form features.',
      ),
    ],
  ),
  // One feed, on purpose — see kSingleFeedStarterCategories. Breaking Muscle
  // was dropped before the first live run (last build date 4 Mar 2025), its
  // replacement BarBend 404s, and so does the Harvard Health blog feed. Do
  // not put breakingmuscle.com back.
  StarterCategory(
    id: 'fitness_health',
    feeds: [
      StarterFeed(
        title: 'Muscle & Fitness',
        url: 'https://www.muscleandfitness.com/feed/',
        siteUrl: 'https://www.muscleandfitness.com',
        description: 'Resistance training, workout routines, sports nutrition, '
            'and supplement breakdowns.',
      ),
    ],
  ),
  // One feed, on purpose — see kSingleFeedStarterCategories. Nomadic Matt and
  // The Planet D are both alive and both useless here: their newest posts on
  // 11 Sep 2026 were 28 Jul and 1 Aug, so applyFetchThresholds keeps nothing
  // from either. A travel *blog* publishes monthly; only a travel *news*
  // operation clears a 7-day window.
  StarterCategory(
    id: 'travel',
    feeds: [
      StarterFeed(
        title: 'The Points Guy',
        url: 'https://thepointsguy.com/feed/',
        siteUrl: 'https://thepointsguy.com',
        description: 'Airline loyalty programs, hotel rewards, flight reviews, '
            'and award travel tactics.',
      ),
    ],
  ),
  StarterCategory(
    id: 'sports',
    feeds: [
      StarterFeed(
        title: 'BBC Sport',
        url: 'https://feeds.bbci.co.uk/sport/rss.xml',
        siteUrl: 'https://www.bbc.com/sport',
        description: 'Global sports updates including football (soccer), '
            'Formula 1, tennis, and athletics.',
      ),
      StarterFeed(
        title: 'ESPN (Top News)',
        url: 'https://www.espn.com/espn/rss/news',
        siteUrl: 'https://www.espn.com',
        description: 'Breaking news and scores across major leagues (NFL, NBA, '
            'MLB, Premier League, combat sports).',
      ),
      StarterFeed(
        title: 'Sky Sports',
        url: 'https://www.skysports.com/rss/12040',
        siteUrl: 'https://www.skysports.com',
        description: 'Live sports news, transfer developments, race coverage, '
            'and league results.',
      ),
    ],
  ),
];
