import { useAuthStore } from "@/store/authStore";
import { useEffect, useState } from "react";
import { Baby, Calendar, CalendarCheck, LineChart, Plus, Trash2, Scale, HeartPulse } from "lucide-react";
import CopyButton from "@/components/CopyButton";
import { healthApi } from "@/api/services";
import type { HealthRecord } from "@/types";
import GrowthChart from "@/components/GrowthChart";
import VaccineCalendar from "@/components/VaccineCalendar";
import HealthCalendar from "@/components/HealthCalendar";
import BmiAnalysisView from "@/components/health/BmiAnalysisView";
import UnifiedHealthCheckIn from "@/components/health/UnifiedHealthCheckIn";

type TabKey = "checkup" | "growth" | "bmi" | "vaccine" | "calendar";

const TABS: Array<{ key: TabKey; label: string; icon: typeof CalendarCheck }> = [
  { key: "checkup", label: "孕产记录", icon: CalendarCheck },
  { key: "growth", label: "生长曲线", icon: LineChart },
  { key: "bmi", label: "体重/BMI分析", icon: Scale },
  { key: "vaccine", label: "疫苗日历", icon: Baby },
  { key: "calendar", label: "日历总览", icon: Calendar },
];

/** 妈妈记录的阶段徽章（v1.55：语义统一后按 exam_items.stage 与孕周判断） */
function MomStageBadge({ record }: { record: HealthRecord }) {
  const stage = record.exam_items?.stage;
  if (stage === "postpartum") {
    return (
      <span className="rounded-full bg-indigo-50 px-2 py-0.5 text-[11px] font-semibold text-indigo-600 dark:bg-indigo-950/50 dark:text-indigo-300">
        产后恢复
      </span>
    );
  }
  if (record.gestational_week) {
    return (
      <span className="rounded-full bg-orange-50 px-2 py-0.5 text-[11px] font-semibold text-brand-600 dark:bg-brand-950/50 dark:text-brand-300">
        孕{record.gestational_week}周
      </span>
    );
  }
  return (
    <span className="rounded-full bg-gray-50 px-2 py-0.5 text-[11px] text-gray-400 dark:bg-gray-800 dark:text-gray-500">
      孕期
    </span>
  );
}

export default function HealthPage() {
  const { hasPermission } = useAuthStore();
  const [tab, setTab] = useState<TabKey>("checkup");
  const [records, setRecords] = useState<HealthRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCheckIn, setShowCheckIn] = useState(false);
  const [toast, setToast] = useState("");
  const [calendarMonth, setCalendarMonth] = useState(() => new Date());

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(""), 2800);
  };

  const load = () => {
    setLoading(true);
    healthApi
      .list()
      .then(setRecords)
      .catch(() => setRecords([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    if (tab !== "bmi") {
      load();
    } else {
      setLoading(false);
    }
  }, [tab]);

  const remove = async (id: number) => {
    if (!window.confirm("确认删除这条记录？")) return;
    try {
      await healthApi.remove(id);
      showToast("已删除");
      load();
    } catch {
      showToast("删除失败，请重试");
    }
  };

  // ===== v1.55 统一数据口径：妈妈记录 = prenatal_exam；宝宝记录 = growth_measurement =====
  const momRecords = records.filter((r) => r.record_type === "prenatal_exam");
  const growthRecords = records.filter((r) => r.record_type === "growth_measurement");

  // 生长曲线数据源：仅宝宝测量记录（妈妈数据不再混入宝宝曲线）
  const growthChartPoints = growthRecords.map((r) => ({
    date: r.record_date,
    weight: r.weight,
    height: r.height,
    head: r.head_circumference,
  }));

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-800 dark:text-gray-100">健康中心</h1>
          <p className="mt-1 text-sm text-gray-400">孕产记录 · 生长曲线 · 体重/BMI · 疫苗日历</p>
        </div>
        {tab !== "vaccine" && tab !== "calendar" && (
          <button
            className="btn-primary"
            onClick={() => setShowCheckIn(true)}
          >
            <Plus className="h-4 w-4" /> 健康打卡
          </button>
        )}
      </div>

      {/* Tab 导航 */}
      <div className="flex flex-wrap gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`flex items-center gap-1.5 rounded-xl px-4 py-2 text-sm transition ${
              tab === t.key
                ? "bg-brand-500 text-white shadow-xs"
                : "border border-gray-100 bg-white text-gray-500 hover:bg-brand-50 dark:border-gray-800 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700"
            }`}
          >
            <t.icon className="h-4 w-4" />
            {t.label}
          </button>
        ))}
      </div>

      {/* 统一健康打卡弹窗（唯一录入入口：妈妈孕期/产后打卡 + 宝宝生长测量） */}
      <UnifiedHealthCheckIn
        isOpen={showCheckIn}
        onClose={() => setShowCheckIn(false)}
        onSaved={(archiveHint) => {
          showToast(archiveHint);
          load();
        }}
      />

      {/* Tab 页面主体切换 */}
      {loading ? (
        <p className="py-10 text-center text-gray-400">加载中…</p>
      ) : tab === "bmi" ? (
        <BmiAnalysisView />
      ) : tab === "checkup" ? (
        <div className="space-y-3">
          {momRecords.length === 0 && (
            <div className="card space-y-2 p-8 text-center">
              <HeartPulse className="mx-auto h-8 w-8 text-gray-300 dark:text-gray-600" />
              <p className="text-sm text-gray-400">
                暂无孕产记录，点击右上角「健康打卡」记录您的第一次产检或产后测量
              </p>
            </div>
          )}
          {momRecords.map((r) => (
            <div key={r.id} className="card flex items-start justify-between">
              <div>
                <div className="flex items-center gap-2">
                  <CalendarCheck className="h-4 w-4 text-brand-500" />
                  <span className="font-medium text-gray-700 dark:text-gray-200">{r.record_date}</span>
                  <MomStageBadge record={r} />
                  {r.weight != null && (
                    <span className="text-[11px] text-gray-400">体重 {r.weight} kg</span>
                  )}
                </div>
                {r.note && (
                  <>
                    <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">{r.note}</p>
                    <div className="mt-1 flex justify-end">
                      <CopyButton text={r.note} label="复制" />
                    </div>
                  </>
                )}
                {r.ai_analysis && (
                  <>
                    <p className="mt-2 rounded-lg bg-cream p-2 text-xs text-gray-500 dark:bg-gray-800/80 dark:text-gray-300">
                      AI 解读：{r.ai_analysis}
                    </p>
                    <div className="mt-1 flex justify-end">
                      <CopyButton text={r.ai_analysis} label="复制" />
                    </div>
                  </>
                )}
              </div>
              {hasPermission("health_record_delete") && (
                <button className="text-gray-300 hover:text-red-500" onClick={() => remove(r.id)}>
                  <Trash2 className="h-4 w-4" />
                </button>
              )}
            </div>
          ))}
        </div>
      ) : tab === "growth" ? (
        <section className="card">
          <h2 className="mb-3 font-semibold text-gray-800 dark:text-gray-100">宝宝生长曲线</h2>
          <GrowthChart points={growthChartPoints} />
          {growthRecords.length === 0 && (
            <p className="py-6 text-center text-sm text-gray-400">
              暂无宝宝生长数据，点击右上角「健康打卡」选择"宝宝·生长测量"录入
            </p>
          )}
        </section>
      ) : tab === "calendar" ? (
        <HealthCalendar
          records={records}
          currentMonth={calendarMonth}
          onMonthChange={setCalendarMonth}
          onDayClick={(_date, dayRecords) => {
            const hasGrowth = dayRecords.some((r) => r.record_type === "growth_measurement");
            const hasMom = dayRecords.some((r) => r.record_type === "prenatal_exam");
            if (hasGrowth) setTab("growth");
            else if (hasMom) setTab("checkup");
            else setTab("vaccine");
          }}
        />
      ) : (
        <VaccineCalendar records={records} onChanged={load} />
      )}

      {toast && (
        <div className="fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-xl bg-gray-900/90 px-4 py-2 text-xs font-medium text-white shadow-lg backdrop-blur">
          {toast}
        </div>
      )}
    </div>
  );
}
