import { abilityAccessCtrl, AbilityConstant, common } from '@kit.AbilityKit';
import { PlaybackContinuation } from './PlaybackContinuation';

/** OS permission and mission availability; the system owns discovery and the continuation trigger. */
export class ContinuationService {
  private static context: common.UIAbilityContext | null = null;
  private static desired: number = -1;
  private static writing: boolean = false;
  private static applied: number = -1;

  static bind(context: common.UIAbilityContext): void {
    ContinuationService.context = context;
    ContinuationService.applied = -1;
    PlaybackContinuation.availabilityChanged = () => ContinuationService.sync();
    ContinuationService.sync();
  }

  static unbind(): void {
    ContinuationService.context = null;
    ContinuationService.desired = -1;
    ContinuationService.applied = -1;
    PlaybackContinuation.availabilityChanged = () => {};
  }

  static granted(context: common.UIAbilityContext): boolean {
    try {
      return abilityAccessCtrl.createAtManager().checkAccessTokenSync(
        context.applicationInfo.accessTokenId, 'ohos.permission.DISTRIBUTED_DATASYNC') ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (e) { return false; }
  }

  static async enable(context: common.UIAbilityContext): Promise<boolean> {
    try {
      if (!ContinuationService.granted(context)) {
        const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
          context, ['ohos.permission.DISTRIBUTED_DATASYNC']);
        if (result.authResults.length === 0 || result.authResults[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return false;
        }
      }
      ContinuationService.sync();
      return true;
    } catch (e) { return false; }
  }

  static sync(): void {
    const context = ContinuationService.context;
    if (context === null) return;
    const active = ContinuationService.granted(context) && PlaybackContinuation.available();
    const state = active ? AbilityConstant.ContinueState.ACTIVE : AbilityConstant.ContinueState.INACTIVE;
    ContinuationService.desired = state;
    ContinuationService.apply(context);
  }

  private static apply(context: common.UIAbilityContext): void {
    if (context !== ContinuationService.context || ContinuationService.writing || ContinuationService.applied === ContinuationService.desired) return;
    const state = ContinuationService.desired;
    ContinuationService.writing = true;
    try {
      context.setMissionContinueState(state).then(() => {
        ContinuationService.writing = false;
        if (context !== ContinuationService.context) {
          ContinuationService.applied = -1;
          ContinuationService.sync();
          return;
        }
        ContinuationService.applied = state;
        ContinuationService.apply(context);
      }).catch(() => {
        ContinuationService.writing = false;
        ContinuationService.applied = -1;
        if (state !== ContinuationService.desired) ContinuationService.apply(context);
      });
    } catch (e) {
      ContinuationService.writing = false;
      ContinuationService.applied = -1;
    }
  }
}
