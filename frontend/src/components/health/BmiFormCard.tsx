import React, { useState, useMemo } from "react";
import { Activity, Sparkles, AlertCircle, Calendar } from "lucide-react";
import type { BmiAnalysisInput, PregnancyStage } from "@/types/health";

interface BmiFormCardProps {
  onSubmit: (data: BmiAnalysisInput) => void;
  loading: boolean;
}

const MEDICAL_HISTORY_OPTIONS = [
  { key: "gdm", label: "妊娠糖尿病 (GDM)" },
  { key: "hypertension", label: "妊娠高血压 / 浮肿" },
  { key: "emesis", label: "剧烈早孕呕吐" },
  { key: "anemia", label: "孕期贫血 / 缺铁" },
  { key: "thyroid", label: "甲状腺功能异常" },
];

export default function BmiFormCard({ onSubmit, loading }: BmiFormCardProps) {
  const [recordDate, setRecordDate] = useState<string>(() => new Date().toISOString().slice(0, 10));
  const [height, setHeight] = useState<string>("163");
  const [preWeight, setPreWeight] = useState<string>("52");
  const [curWeight, setCurWeight] = useState<string>("57");
  const [waistCircumference, setWaistCircumference] = useState<string>("");
  const [stageType, setStageType] = useState<PregnancyStage>("pregnancy");
  const [gestationalWeek, setGestationalWeek] = useState<string>("24");
  const [postpartumMonths, setPostpartumMonths] = useState<string>("2");
  const [isTwins, setIsTwins] = useState<boolean>(false);
  const [medicalHistory, setMedicalHistory] = useState<string[]>([]);
  const [errorMsg, setErrorMsg] = useState<string>("");

  const instantBmi = useMemo(() => {
    const h = parseFloat(height);
    const pw = parseFloat(preWeight);
    if (h > 90 && h < 230 && pw > 30 && pw < 200) {
      const meter = h / 100;
      return +(pw / (meter * meter)).toFixed(2);
    }
    return null;
  }, [height, preWeight]);

  const bmiCategoryLabel = useMemo(() => {
    if (instantBmi === null) return "";
    if (instantBmi < 18.5) return "低体重 (BMI < 18.5)";
    if (instantBmi < 24.0) return "正常体重 (18.5 ~ 23.9)";
    if (instantBmi < 28.0) return "超重 (24.0 ~ 27.9)";
    return "肥胖 (BMI ≥ 28.0)";
  }, [instantBmi]);

  const toggleHistory = (key: string) => {
    setMedicalHistory((prev) =>
      prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]
    );
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg("");

    const hNum = parseFloat(height);
    const pwNum = parseFloat(preWeight);
    const cwNum = parseFloat(curWeight);

    if (isNaN(hNum) || hNum < 100 || hNum > 230) {
      setErrorMsg("请输入合理的身高 (100 ~ 230 cm)");
      return;
    }
    if (isNaN(pwNum) || pwNum < 30 || pwNum > 200) {
      setErrorMsg("请输入合理的孕前体重 (30 ~ 200 kg)");
      return;
    }
    if (isNaN(cwNum) || cwNum < 30 || cwNum > 220) {
      setErrorMsg("请输入合理的当前体重 (30 ~ 220 kg)");
      return;
    }

    const payload: BmiAnalysisInput = {
      record_date: recordDate || undefined,
      height_cm: hNum,
      pre_pregnancy_weight_kg: pwNum,
      current_weight_kg: cwNum,
      stage_type: stageType,
      is_twins: isTwins,
      medical_history: medicalHistory,
      save_record: true,
    };

    if (waistCircumference) {
      const wcNum = parseFloat(waistCircumference);
      if (!isNaN(wcNum) && wcNum >= 30 && wcNum <= 200) {
        payload.waist_circumference_cm = wcNum;
      }
    }

    if (stageType === "pregnancy") {
      const gwNum = parseInt(gestationalWeek, 10);
      if (isNaN(gwNum) || gwNum < 1 || gwNum > 42) {
        setErrorMsg("请输入有效的孕周 (1 ~ 42周)");
        return;
      }
      payload.gestational_week = gwNum;
    } else {
      const pmNum = parseInt(postpartumMonths, 10);
      payload.postpartum_months = isNaN(pmNum) ? 1 : pmNum;
    }

    onSubmit(payload);
  };

  return (
    <div className="card space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-orange-100/60 pb-3 dark:border-gray-800">
        <div className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-brand-50 text-brand-600 dark:bg-brand-950/60 dark:text-brand-400">
            <Activity className="h-4 w-4" />
          </div>
          <div>
            <h3 className="text-base font-bold text-gray-800 dark:text-gray-100">
              时序身高体重录入与打卡 (WS/T 801-2022)
            </h3>
            <p className="text-xs text-gray-400">
              支持按天自定义日期补录，测量数据将默认自动持久化归档至健康档案时序库
            </p>
          </div>
        </div>
        {instantBmi !== null && (
          <div className="flex items-center gap-2 rounded-xl bg-orange-50/70 px-3 py-1.5 text-xs font-semibold text-brand-700 dark:bg-brand-950/40 dark:text-brand-300">
            <span>孕前 BMI：{instantBmi}</span>
            <span className="rounded-full bg-brand-200/60 px-2 py-0.5 text-[11px] text-brand-800 dark:bg-brand-900/60 dark:text-brand-200">
              {bmiCategoryLabel}
            </span>
          </div>
        )}
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        {errorMsg && (
          <div className="flex items-center gap-2 rounded-xl bg-red-50 p-3 text-xs text-red-600 dark:bg-red-950/30 dark:text-red-400">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>{errorMsg}</span>
          </div>
        )}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <label className="label flex items-center gap-1">
              <Calendar className="h-3.5 w-3.5 text-brand-500" />
              <span>测量日期 (支持按天补录) *</span>
            </label>
            <input
              type="date"
              className="input font-medium"
              value={recordDate}
              onChange={(e) => setRecordDate(e.target.value)}
              required
            />
          </div>

          <div>
            <label className="label">阶段类型 *</label>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setStageType("pregnancy")}
                className={`flex-1 rounded-xl py-2 text-xs font-semibold transition-all ${
                  stageType === "pregnancy"
                    ? "bg-brand-500 text-white shadow-xs"
                    : "bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-300"
                }`}
              >
                全孕期阶段
              </button>
              <button
                type="button"
                onClick={() => setStageType("postpartum")}
                className={`flex-1 rounded-xl py-2 text-xs font-semibold transition-all ${
                  stageType === "postpartum"
                    ? "bg-brand-500 text-white shadow-xs"
                    : "bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-300"
                }`}
              >
                产后母乳/恢复期
              </button>
            </div>
          </div>

          <div>
            {stageType === "pregnancy" ? (
              <>
                <label className="label">当前孕周 (1 ~ 42 周) *</label>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    min="1"
                    max="42"
                    className="input"
                    placeholder="例如 24"
                    value={gestationalWeek}
                    onChange={(e) => setGestationalWeek(e.target.value)}
                    required
                  />
                  <span className="text-xs text-gray-400">周</span>
                </div>
              </>
            ) : (
              <>
                <label className="label">产后月龄 (0 ~ 36 个月) *</label>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    min="0"
                    max="36"
                    className="input"
                    placeholder="例如 2"
                    value={postpartumMonths}
                    onChange={(e) => setPostpartumMonths(e.target.value)}
                    required
                  />
                  <span className="text-xs text-gray-400">个月</span>
                </div>
              </>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
          <div>
            <label className="label">身高 (cm) *</label>
            <input
              type="number"
              className="input"
              placeholder="例如 163"
              value={height}
              onChange={(e) => setHeight(e.target.value)}
              required
            />
          </div>

          <div>
            <label className="label">孕前体重 (kg) *</label>
            <input
              type="number"
              step="0.1"
              className="input"
              placeholder="例如 52.0"
              value={preWeight}
              onChange={(e) => setPreWeight(e.target.value)}
              required
            />
          </div>

          <div>
            <label className="label">本次实测体重 (kg) *</label>
            <input
              type="number"
              step="0.1"
              className="input"
              placeholder="例如 57.2"
              value={curWeight}
              onChange={(e) => setCurWeight(e.target.value)}
              required
            />
          </div>

          <div>
            <label className="label">腹围 (cm, 选填)</label>
            <input
              type="number"
              step="0.5"
              className="input"
              placeholder="例如 85.0"
              value={waistCircumference}
              onChange={(e) => setWaistCircumference(e.target.value)}
            />
          </div>
        </div>

        {stageType === "pregnancy" && (
          <div className="flex items-center gap-3 pt-1">
            <label className="relative inline-flex cursor-pointer items-center">
              <input
                type="checkbox"
                checked={isTwins}
                onChange={(e) => setIsTwins(e.target.checked)}
                className="peer sr-only"
              />
              <div className="peer h-5 w-9 rounded-full bg-gray-200 after:absolute after:left-[2px] after:top-[2px] after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-all after:content-['] peer-checked:bg-brand-500 peer-checked:after:translate-x-full dark:bg-gray-700" />
              <span className="ml-2 text-xs font-semibold text-gray-700 dark:text-gray-300">
                双胎妊娠 (WS/T 801-2022 双胎标准，总推荐增重 16.8~24.5 kg)
              </span>
            </label>
          </div>
        )}

        <div>
          <label className="label">合并情况 / 代谢特征 (用于个性化膳食控糖控盐与禁忌食材定向筛查)</label>
          <div className="flex flex-wrap gap-2 pt-1">
            {MEDICAL_HISTORY_OPTIONS.map((item) => {
              const active = medicalHistory.includes(item.key);
              return (
                <button
                  type="button"
                  key={item.key}
                  onClick={() => toggleHistory(item.key)}
                  className={`rounded-xl border px-3 py-1.5 text-xs font-medium transition-all ${
                    active
                      ? "border-brand-500 bg-brand-50 text-brand-700 shadow-2xs dark:border-brand-500 dark:bg-brand-950/60 dark:text-brand-300"
                      : "border-gray-200 bg-white text-gray-600 hover:border-gray-300 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-400"
                  }`}
                >
                  {item.label}
                </button>
              );
            })}
          </div>
        </div>

        <div className="flex items-center justify-between border-t border-orange-100/60 pt-3 dark:border-gray-800">
          <p className="text-xs text-gray-400">
            ✓ 测量数据默认自动持久化保存至健康中心时序库，可随时在图表看板回溯
          </p>

          <button
            type="submit"
            disabled={loading}
            className="btn-primary gap-1.5 px-6 py-2.5 text-sm font-semibold shadow-md shadow-brand-500/20"
          >
            <Sparkles className="h-4 w-4" />
            {loading ? "正在综合分析与推荐食谱…" : "一键分析评估 & 归档至时序档案"}
          </button>
        </div>
      </form>
    </div>
  );
}
