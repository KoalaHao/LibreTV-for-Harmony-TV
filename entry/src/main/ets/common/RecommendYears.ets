/** Recommendation years are sent to the provider; they never filter just the already loaded page. */
export class RecommendYears {
  static options(currentYear: number = new Date().getFullYear()): string[] {
    const options: string[] = ['全部'];
    for (let year = currentYear; year >= currentYear - 6; year--) options.push(year.toString());
    const decade = Math.floor(currentYear / 10) * 10;
    for (let year = decade; year >= decade - 50; year -= 10) options.push(year.toString() + '年代');
    options.push('更早');
    return options;
  }

  static range(label: string, currentYear: number = new Date().getFullYear()): string {
    if (label === '更早') return '1900,' + (Math.floor(currentYear / 10) * 10 - 51).toString();
    if (/^\d{4}$/.test(label)) {
      const year = Number(label);
      return year >= 1900 && year <= currentYear ? label + ',' + label : '';
    }
    if (/^\d{4}年代$/.test(label)) {
      const year = Number(label.substring(0, 4));
      if (year >= 1900 && year <= currentYear && year % 10 === 0) {
        return year.toString() + ',' + Math.min(year + 9, currentYear).toString();
      }
    }
    return '';
  }
}
