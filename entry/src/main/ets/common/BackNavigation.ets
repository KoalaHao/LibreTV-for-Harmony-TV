/** Routes system Back to the visible destination before the Ability can leave the app. */
export class BackNavigation {
  private static handlers: Map<string, () => void> = new Map();

  static register(route: string, handler: () => void): void {
    BackNavigation.handlers.set(route, handler);
  }

  static clear(): void {
    BackNavigation.handlers.clear();
  }

  static dispatch(paths: string[], pop: () => void, home: () => void): boolean {
    if (paths.length > 0) {
      const handler = BackNavigation.handlers.get(paths[paths.length - 1]);
      if (handler !== undefined) handler();
      else pop();
    } else {
      home();
    }
    // @Entry.onBackPress true consumes Back; UIAbility.onBackPressed true would background the app.
    return true;
  }
}
