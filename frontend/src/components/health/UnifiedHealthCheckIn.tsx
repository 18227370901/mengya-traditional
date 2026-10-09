import { useEffect, useMemo, useState } from "react";
import {
  HeartPulse,
  Baby,
  PersonStanding,
  Calendar,
  Scale,
  Ruler,
  Loader2,
  CheckCircle2,
  X,
  Info,
} from "lucide-react";
import { useAuthStore } from "@/store/authStore";
import { healthApi } from "@/api/services";
import type { BmiAnalysisInput, HealthRecord } from "@/types";

/**
 * 统一健康打卡弹窗（v1.55 健康中心唯一录入入口）
 * 按"记录对象"分流：我·孕期产检 / 我·产后恢复 / 宝宝·生长测量，
 * 档案智能默认 + 孕周/月龄自动推算，数据自动归档至孕产记录/BMI时序/生长曲线/日历。
 */

type CheckInMode = "mom_pregnancy" | "mom_postpartum" | "baby";

interface UnifiedHealthCheckInProps {
  isOpen: boolean;
  onClose: () => void;
  /** 保存成功后回调，参数为归档去向提示文案 */
  onSaved: (archiveHint: string) => void;
}

/** 基于预产期的 280 天医学模型自动推算孕周（与后端 gestation_engine 保持一致） */
function autoWeekFromDueDate(dueDate: string, recordDate: string): number | null {
  const due = new Date(dueDate);
  const rec = new Date(recordDate);
  if (Number.isNaN(due.getTime()) || Number.isNaN(rec.getTime())) return null;
  const lmp = due.getTime() - 280 * 86400000;
  const days = Math.floor((rec.getTime() - lmp) / 86400000);
  if (days < 0) return 0;
  return Math.min(40, Math.floor(days / 7));
}

/** 依据宝宝生日自动推算天数差 */
function daysBetween(fromDate: string, toDate: string): number | null {
  const from = new Date(fromDate);
  const to = new Date(toDate);
  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) return null;
  return Math.max(0, Math.floor((to.getTime() - from.getTime()) / 86400000));
}

export default function UnifiedHealthCheckIn({ isOpen, onClose, onSaved }: UnifiedHealthCheckInProps) {
  const { user } = useAuthStore();
  const hasDueDate = !!user?.due_date;
  const hasBabyBirthday = !!user?.baby_birthday;

  const [mode, setMode] = useState<CheckInMode>("mom_pregnancy");
  const [recordDate, setRecordDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [weight, setWeight] = useState("");
  const [waist, setWaist] = useState("");
  const [manualWeek, setManualWeek] = useState("");
  const [babyHeight, setBabyHeight] = useState("");
  const [babyWeight, setBabyWeight] = useState("");
  const [babyHead, setBabyHead] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState("");

  // 档案智能默认：孕期用户默认孕期打卡；已出生宝宝档案默认宝宝测量；均未设置默认孕期
  useEffect(() => {
    if (!isOpen) return;
    setErrorMsg("");
    if (user?.is_pregnant) {
      setMode("mom_pregnancy");
    } else if (user?.baby_birthday) {
      setMode("baby");
    } else {
      setMode("mom_pregnancy");
    }
    setRecordDate(new Date().toISOString().slice(0, 10));
    setWeight("");
    setWaist("");
    setManualWeek("");
    setBabyHeight("");
    setBabyWeight("");
    setBabyHead("");
    setNote("");
  }, [isOpen, user?.is_pregnant, user?.baby_birthday]);

  // 孕周自动推算（有预产期时）
  const autoWeek = useMemo(() => {
    if (mode !== "mom_pregnancy" || !user?.due_date) return null;
    return autoWeekFromDueDate(user.due_date, recordDate);
  }, [mode, user?.due_date, recordDate]);

  // 产后天数 / 宝宝天数自动推算
  const babyDays = useMemo(() => {
    if (!user?.baby_birthday) return null;
    return daysBetween(user.baby_birthday, recordDate);
  }, [user?.baby_birthday, recordDate]);

  const babyAgeText = useMemo(() => {
    if (babyDays == null) return null;
    if (babyDays < 30) return `${babyDays} 天`;
    const months = Math.floor(babyDays / 30.44);
    return `${months} 个月（${babyDays} 天）`;
  }, [babyDays]);

  if (!isOpen) return null;

  const isBabyMode = mode === "baby";
  const isPostpartumMode = mode === "mom_postpartum";
  const momMode = mode === "mom_pregnancy";

  const MODE_OPTIONS: Array<{
    key: CheckInMode;
    label: string;
    desc: string;
    icon: typeof HeartPulse;
  }> = [
    {
      key: "mom_pregnancy",
      label: "我 · 孕期产检",
      desc: hasDueDate ? "孕周按预产期自动推算" : "需手填孕周，建议先设置预产期",
      icon: PersonStanding,
    },
    {
      key: "mom_postpartum",
      label: "我 · 产后恢复",
      desc: hasBabyBirthday ? "产后天数按宝宝生日自动推算" : "记录产后体重恢复走势",
      icon: HeartPulse,
    },
    {
      key: "baby",
      label: "宝宝 · 生长测量",
      desc: hasBabyBirthday ? "月龄按宝宝生日自动推算" : "身高/体重/头围生长曲线",
      icon: Baby,
    },
  ];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg("");
    const w = Number(weight);

    // ===== 前端轻量校验 =====
    if (!isBabyMode) {
      if (!weight || Number.isNaN(w) || w <= 0) {
        setErrorMsg("请填写本次实测体重 (kg)");
        return;
      }
      if (momMode && !hasDueDate && !manualWeek) {
        setErrorMsg("您还未设置预产期，请手动填写本次打卡的孕周");
        return;
      }
    } else {
      const hasAnyMeasure = babyHeight || babyWeight || babyHead;
      if (!hasAnyMeasure) {
        setErrorMsg("宝宝测量至少填写身高、体重、头围中的一项");
        return;
      }
    }

    setSaving(true);
    try {
      if (isBabyMode) {
        // ===== 宝宝生长测量 → growth_measurement（生长曲线/日历）=====
        const babyPayload: Partial<HealthRecord> = {
          record_type: "growth_measurement",
          record_date: recordDate,
          baby_age_days: babyDays ?? undefined,
          height: babyHeight ? Number(babyHeight) : undefined,
          weight: babyWeight ? Number(babyWeight) : undefined,
          head_circumference: babyHead ? Number(babyHead) : undefined,
          note: note || undefined,
        };
        await healthApi.create(babyPayload);
        onSaved("宝宝测量已归档：生长曲线 · 日历总览");
      } else {
        // ===== 妈妈打卡（孕期/产后）→ BMI 分析接口（自动孕周校验 + 基线继承 + WS/T 评估）=====
        const payload: BmiAnalysisInput = {
          stage_type: isPostpartumMode ? "postpartum" : "pregnancy",
          record_date: recordDate,
          current_weight_kg: w,
          waist_circumference_cm: waist ? Number(waist) : undefined,
          medical_history: [],
          is_twins: false,
        };
        if (momMode) {
          payload.gestational_week = hasDueDate ? (autoWeek ?? undefined) : Number(manualWeek);
        } else {
          payload.postpartum_months = babyDays != null ? Math.max(0, Math.floor(babyDays / 30.44)) : 1;
        }
        await healthApi.analyzeBmi(payload);
        onSaved(
          isPostpartumMode
            ? "产后打卡已归档：孕产记录 · BMI 时序 · 日历"
            : "孕期打卡已归档：孕产记录 · BMI 时序与医学评估 · 日历"
        );
      }
      onClose();
    } catch (err: any) {
      // 透传后端孕周校验拦截等业务错误信息
      const data = err?.response?.data;
      setErrorMsg(data?.message || err?.message || "保存失败，请稍后重试");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs">
      <div className="relative max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl transition-all dark:bg-gray-800 dark:text-gray-100">
        <button
          onClick={onClose}
          className="absolute right-4 top-4 rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-700 dark:hover:text-gray-200"
          type="button"
          aria-label="关闭"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="flex items-center gap-2.5 border-b border-gray-100 pb-3 dark:border-gray-700">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-orange-100 text-brand-600 dark:bg-brand-950 dark:text-brand-400">
            <HeartPulse className="h-5 w-5" />
          </div>
          <div>
            <h3 className="text-base font-bold text-gray-800 dark:text-gray-100">健康打卡</h3>
            <p className="text-xs text-gray-400">
              一次录入，自动同步孕产记录 · BMI 时序 · 生长曲线 · 日历总览
            </p>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          {errorMsg && (
            <div className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-xs leading-relaxed text-red-600 dark:bg-red-950/30 dark:text-red-400">
              <Info className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}

          {/* 分区 1：记录对象（按档案智能默认，可自由切换覆盖补录场景） */}
          <div>
            <label className="label">① 我要记录</label>
            <div className="grid grid-cols-3 gap-2">
              {MODE_OPTIONS.map((opt) => (
                <button
                  key={opt.key}
                  type="button"
                  onClick={() => {
                    setMode(opt.key);
                    setErrorMsg("");
                  }}
                  className={`flex flex-col items-center gap-1 rounded-xl border p-3 text-center transition ${
                    mode === opt.key
                      ? "border-brand-400 bg-brand-50 shadow-xs dark:border-brand-600 dark:bg-brand-950/50"
                      : "border-gray-100 bg-white hover:border-brand-200 dark:border-gray-700 dark:bg-gray-800"
                  }`}
                >
                  <opt.icon
                    className={`h-5 w-5 ${mode === opt.key ? "text-brand-600 dark:text-brand-400" : "text-gray-400"}`}
                  />
                  <span
                    className={`text-xs font-semibold ${
                      mode === opt.key ? "text-brand-700 dark:text-brand-300" : "text-gray-600 dark:text-gray-300"
                    }`}
                  >
                    {opt.label}
                  </span>
                </button>
              ))}
            </div>
            <p className="mt-1.5 text-[11px] text-gray-400">
              {MODE_OPTIONS.find((o) => o.key === mode)?.desc}
            </p>
          </div>

          {/* 分区 2：日期（默认今天，支持补录；自动回显孕周/产后天数/宝宝月龄） */}
          <div>
            <label className="label flex items-center gap-1">
              <Calendar className="h-3.5 w-3.5 text-gray-400" />
              ② 测量日期（支持补录历史）
            </label>
            <input
              type="date"
              className="input"
              value={recordDate}
              onChange={(e) => setRecordDate(e.target.value)}
              required
            />
            {momMode && hasDueDate && autoWeek != null && (
              <p className="mt-1 text-[11px] text-emerald-600 dark:text-emerald-400">
                <CheckCircle2 className="mr-0.5 inline h-3 w-3" />
                按档案预产期自动记录为：孕 {autoWeek} 周（无需手填，后端同步校验）
              </p>
            )}
            {isPostpartumMode && babyDays != null && (
              <p className="mt-1 text-[11px] text-emerald-600 dark:text-emerald-400">
                <CheckCircle2 className="mr-0.5 inline h-3 w-3" />
                产后 {babyAgeText}，将自动归档为产后恢复打卡
              </p>
            )}
            {isBabyMode && babyAgeText && (
              <p className="mt-1 text-[11px] text-emerald-600 dark:text-emerald-400">
                <CheckCircle2 className="mr-0.5 inline h-3 w-3" />
                宝宝月龄自动推算：{babyAgeText}
              </p>
            )}
          </div>

          {/* 分区 3：动态指标 */}
          <div>
            <label className="label">③ 测量指标</label>

            {!isBabyMode ? (
              <div className="space-y-3">
                {momMode && !hasDueDate && (
                  <div>
                    <label className="text-xs text-gray-500 dark:text-gray-400">孕周 (1~42) *</label>
                    <input
                      type="number"
                      min={1}
                      max={42}
                      className="input"
                      placeholder="例如 24"
                      value={manualWeek}
                      onChange={(e) => setManualWeek(e.target.value)}
                      required
                    />
                  </div>
                )}
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="text-xs text-gray-500 dark:text-gray-400">本次体重 (kg) *</label>
                    <div className="relative">
                      <Scale className="absolute left-3 top-3 h-4 w-4 text-gray-400" />
                      <input
                        type="number"
                        step="0.1"
                        min={30}
                        max={220}
                        className="input pl-9"
                        placeholder="例如 58.2"
                        value={weight}
                        onChange={(e) => setWeight(e.target.value)}
                        required
                      />
                    </div>
                  </div>
                  <div>
                    <label className="text-xs text-gray-500 dark:text-gray-400">腹围 (cm, 选填)</label>
                    <input
                      type="number"
                      step="0.1"
                      min={30}
                      max={200}
                      className="input"
                      placeholder="例如 86.0"
                      value={waist}
                      onChange={(e) => setWaist(e.target.value)}
                    />
                  </div>
                </div>
                <p className="text-[11px] text-gray-400">
                  身高与孕前体重将自动继承上次打卡基线，无需重复填写
                </p>
              </div>
            ) : (
              <div className="grid grid-cols-3 gap-3">
                <div>
                  <label className="text-xs text-gray-500 dark:text-gray-400">身高 (cm)</label>
                  <div className="relative">
                    <Ruler className="absolute left-3 top-3 h-4 w-4 text-gray-400" />
                    <input
                      type="number"
                      step="0.1"
                      className="input pl-9"
                      placeholder="身高"
                      value={babyHeight}
                      onChange={(e) => setBabyHeight(e.target.value)}
                    />
                  </div>
                </div>
                <div>
                  <label className="text-xs text-gray-500 dark:text-gray-400">体重 (kg)</label>
                  <div className="relative">
                    <Scale className="absolute left-3 top-3 h-4 w-4 text-gray-400" />
                    <input
                      type="number"
                      step="0.1"
                      className="input pl-9"
                      placeholder="体重"
                      value={babyWeight}
                      onChange={(e) => setBabyWeight(e.target.value)}
                    />
                  </div>
                </div>
                <div>
                  <label className="text-xs text-gray-500 dark:text-gray-400">头围 (cm)</label>
                  <input
                    type="number"
                    step="0.1"
                    className="input"
                    placeholder="头围"
                    value={babyHead}
                    onChange={(e) => setBabyHead(e.target.value)}
                  />
                </div>
              </div>
            )}
          </div>

          <div>
            <label className="label">备注 (选填)</label>
            <input
              className="input"
              placeholder="如：胎心正常 / 医生建议 / 本次测量感受"
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </div>

          <div className="flex items-center justify-end gap-2 border-t border-gray-100 pt-4 dark:border-gray-700">
            <button type="button" onClick={onClose} className="btn-secondary text-xs" disabled={saving}>
              取消
            </button>
            <button type="submit" className="btn-primary gap-1.5 text-xs shadow-md shadow-brand-500/20" disabled={saving}>
              {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CheckCircle2 className="h-3.5 w-3.5" />}
              保存打卡
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
