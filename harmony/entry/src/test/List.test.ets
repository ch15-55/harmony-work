import budgetTextUtilTest from './BudgetTextUtil.test';
import appLockLogicTest from './AppLockLogic.test';
import moneyUtilTest from './MoneyUtil.test';
import dateUtilTest from './DateUtil.test';
import moneyCurrencyTest from './MoneyCurrency.test';
import serviceLocatorTest from './ServiceLocator.test';

export default function testsuite() {
  budgetTextUtilTest();
  appLockLogicTest();
  moneyUtilTest();
  dateUtilTest();
  moneyCurrencyTest();
  serviceLocatorTest();
}
